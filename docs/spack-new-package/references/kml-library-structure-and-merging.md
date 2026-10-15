# KML 数学库内部结构与合并分析

> 来源：2026-09-01 会话，在鲲鹏920 HPCKit 26.0.RC1 上用 nm/readelf/objcopy/patchelf 实测验证
> 场景：用户问能否像 OpenBLAS 那样把 KBLAS+KLAPACK 合成单个 libkopenblas.so

## 库文件布局（gcc 版，sve 优化）

```
/opt/HPCKit/26.0.RC1/kml/gcc/lib/
├── sve/                           ← SVE 优化版（鲲鹏920 首选）
│   ├── kblas/
│   │   ├── multi/libkblas.so      ← BLAS 实现（闭源，只有 .so，无 .a）
│   │   ├── locking/libkblas.so    ← 加锁版（多线程安全）
│   │   └── nolocking/libkblas.so  ← 无锁版（单线程/自管线程安全）
│   ├── libklapack.so              ← KML 优化的 LAPACK（仅少数关键函数）
│   ├── libklapack.a               ← 同上静态库（缺 _netlib_ 参考实现）
│   ├── libklapack_full.so         ← 完整 LAPACK = KML优化 + Netlib参考实现（预编译）
│   ├── libkservice.a / .so        ← KML 服务层（KmlGetMaxThreads 等）
│   ├── libksolver.a               ← KML 求解器
│   └── libkscalapack.a            ← KML ScaLAPACK
├── sve512/                        ← SVE 512-bit 优化版
├── neon/                          ← NEON 版（兼容性回退）
├── noarch/
│   ├── libkm.so                   ← KML 公共运行时（架构无关）
│   └── kvml/                      ← KML 向量数学库
└── lib/libkml_rt.so               ← KML 运行时入口
```

BiSheng 编译器版本在 `kml/bisheng/lib/` 下，结构相同。

## 符号依赖关系（关键）

用 `nm -D` 验证的符号状态：

| 符号 | libklapack_full.so | libkblas.so | libkservice.a | 说明 |
|------|-------------------|------------|---------------|------|
| `dpotrf_` (LAPACK) | T | — | — | LAPACK 实现在 full.so |
| `dgemm_` (BLAS) | **U** | T | — | BLAS 实现在 kblas.so，full.so 只引用 |
| `dpotrf_netlib_` | T | — | — | Netlib 参考实现也在 full.so |
| `KmlGetMaxThreads` | — | — | T | 服务层符号 |
| `cblas_dgemm` | — | T | — | CBLAS 接口在 kblas.so |

**核心事实**：`libklapack_full.so` 已包含完整 LAPACK（KML 优化 + Netlib 参考），但所有 BLAS 符号（118 个 Fortran 接口）是 U（未定义），运行时需从 `libkblas.so` 解析。

## 为什么不能合成单个 libkopenblas.so

OpenBLAS 能做成单个库是因为 BLAS/LAPACK 实现都从源码编译进库（符号为 T）。KML 的 BLAS 是闭源 .so，无法物理内联。实测验证了 4 种方案全部失败：

| 方案 | 做法 | 失败原因 |
|------|------|---------|
| libklapack.a + libkblas.so 链接 | `gcc -shared --whole-archive libklapack.a -lkblas` | libkblas 只有 .so，不能 whole-archive；BLAS 符号保持 U |
| objcopy 从 .so 提取 .o | `objcopy libkblas.so → .o` | .so 是已链接 ELF，提取后符号丢失 |
| patchelf 添加 NEEDED | 复制 full.so + `patchelf --add-needed libkblas.so.1` | 用户编译时 ld 报 `DSO missing from command line`；现代 ld（binutils 2.28+）默认不搜索传递依赖 |
| ifunc trampoline + libklapack.a | 生成 118 个 BLAS ifunc 转发 | libklapack.a 缺 `_netlib_` 参考实现符号（只在 full.so 中有定义） |

**根本原因**：GNU ld 不从 .so 的传递 NEEDED 依赖解析未定义符号（安全特性，默认关闭 `--copy-dt-needed-entries`）。

## 可行方案

### 方案 A：编译 Netlib LAPACK 源码 + ifunc trampoline（真正的单个 .so）

华为生成 `libklapack_full.so` 的方法，自己做一遍：

1. 下载 Netlib LAPACK 3.12.0 源码（https://github.com/Reference-LAPACK/lapack/archive/refs/tags/v3.12.0.tar.gz）
2. 编译参考实现 `liblapack_adapt.a`（修改 Makefile 让 BLAS 调用走 KBLAS）
3. 生成 BLAS 符号的 ifunc trampoline（自动生成 118 个 `__attribute__((ifunc))` 转发函数）
4. 合并：`libklapack.a + liblapack_adapt.a + libkservice.a + trampoline.o → libkopenblas.so`
5. NEEDED 依赖 `libkblas.so.1`（运行时提供 BLAS 实现）

ifunc trampoline 代码模板（已验证可编译）：
```c
#define _GNU_SOURCE
#include <dlfcn.h>
static void* resolve_from_kblas(const char* name) {
    void* ptr = dlsym(RTLD_NEXT, name);
    if (!ptr) ptr = dlsym(RTLD_DEFAULT, name);
    return ptr;
}
// 每个符号一个 resolver + ifunc 声明
static void* resolve_dgemm(void) { return resolve_from_kblas("dgemm_"); }
void dgemm_(void) __attribute__((ifunc("resolve_dgemm")));
```

生成脚本思路（Python）：从 `readelf --dyn-syms libklapack_full.so` 提取所有 UND 的以 `_` 结尾的 Fortran 符号，与 `nm -D libkblas.so` 的 T 符号取交集，为每个符号生成 resolver + ifunc 声明。

### 方案 B：pkg-config 封装（两个 .so，用户体验等价）

不追求物理合并，部署 `libklapack_full.so` + `libkblas.so` + pkg-config 文件：
```
# kopenblas.pc
Libs: -L/opt/kopenblas/lib -lklapack_full -lkblas -lkm -lgomp -lgfortran
Cflags: -I/opt/kopenblas/include
```

## 环境注意事项

- **OMP_5.0.1 版本问题**：KBLAS multi 版需要 HPCKit GCC 的 libgomp.so.1（支持 OMP_5.0.1），系统 libgomp 不支持。构建时必须用 HPCKit 的 gcc（`/opt/HPCKit/26.0.RC1/compiler/gcc/bin/gcc`）并在 rpath 中包含 `/opt/HPCKit/26.0.RC1/compiler/gcc/lib64`。
- **KML LAPACK 多线程**：调用 KML LAPACK 时会多线程调用 KML BLAS，因此不可用 nolocking 版 KBLAS，推荐 multi（OpenMP）版。
- **精度选择**：KBLAS 分 neon/sve/sve512/sme 四种指令集优化版，鲲鹏920 首选 sve 或 sve512。
- **libkm.so 位置**：在 `kml/<variant>/lib/noarch/` 下，是架构无关的公共运行时，所有 KML 库都依赖它。
