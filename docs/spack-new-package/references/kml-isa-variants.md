# KML（HPCKit 数学库）多指令集变体选型 + 向量长度约束

实测环境：aarch64 鲲鹏 920（CPU implementer=0x48, part=0xd22），HPCKit `26.0.RC1`（`/opt/HPCKit/26.0.RC1/kml/gcc`），
另对照 `25.1.0`（/opt/HPCKit）与 `26.1.RC1`（spack 安装树）。用户问「matrix/neon/noarch/sve/sve512/sve_no_f64mm 有什么区别、怎么选」时，直接按本文回答。

## 1. 目录语义：同一套 API 各编一份，选型 = 只换 LD_LIBRARY_PATH

`kml/{gcc,bisheng}/lib/` 下每个子目录是**同一套 ABI（同名 .so、同 SONAME）按不同指令集各编译一份**，
所以切换指令集**不需要改代码、不需要重编译应用**，只要改 `LD_LIBRARY_PATH`。

| 目录 | 指令集 / 编译假设 | 内含组件 |
|---|---|---|
| `neon/` | NEON(ASIMD) 128bit + dotprod，**与 VL 无关** | kblas + kspblas + kfft + klapack + kscalapack + ksolver + ksvml + kipl |
| `sve/` | SVE **固定 256bit**（`-msve-vector-bits=256`）+ SVE FP16 `fmlal` | 同上 + MPI 版 FFT(`libkfft*_mpi`) + libkconv |
| `sve512/` | SVE **512bit**，klapack 内还含 SME `fmopa` | kfft/MPI-kfft、klapack、kscalapack、ksolver、kscasolver、kipl、ksvml、kconv、kspblas —— **没有 kblas** |
| `sve_no_f64mm/` | SVE 256bit 但**不带 F64MM** 的 KFFT 专用版 | 仅 KFFT 家族（kfft/kfftf/kffth + `_mpi`）；part 0xd06 缺 F64MM，通用 `sve/` 版 KFFT 在其上不可用 |
| `sme/`（25.1.0、26.0.RC1）→ **`matrix/`**（26.1.RC1 起改名） | **SME 矩阵扩展**（`fmopa`，另有 bf16 `bgemm`） | **只有 kblas**（multi/locking/nolocking） |
| `noarch/` | 与指令集无关（标量/通用 + 运行时按 CPU 分派） | libkm(MATH)、libkvsl、libkes、libknpy、`libkml_rt`、libklapack_full、libfftw3/fftw3f、libpetsc/HYPRE/dmumps、kvml/{single,multi}、java jar |

`libkml_rt.so`（`$K/lib/` 根）是运行时层：导出全套 BLAS/LAPACK/BLACS 符号 + 按 CPU `dlopen` 挑子目录，受 `KML_*_TYPE` 环境变量控制。
实测：遍历所有 KML .so 的 `DT_NEEDED`，**没有任何库依赖它**，所以它只在应用显式链接时生效。

## 2. 怎么选：照抄 setvars.sh / modulefiles 的权威规则（不要自己猜）

`kml/gcc/env/setvars.sh` 与 `modulefiles/kml` 里的映射（`implementer=0x48` 华为）：

| CPU part | `libdir`（除 kblas 外全部组件） | `kblaslibdir` |
|---|---|---|
| `0xd01` | `neon` | `neon`（链接期另加 matrix/sme 目录解析 bf16 `bgemm` 符号） |
| `0xd02` / `0xd03` | `sve` | `sve` |
| `0xd06` | `sve`，**KFFT 换 `sve_no_f64mm`** | `sve` |
| `0xd22` | **`sve512`** | **`matrix`**（26.0.RC1/25.1.0 中叫 `sme`） |
| 其他 | `neon` | `neon` |

```bash
source /opt/HPCKit/<ver>/kml/gcc/env/setvars.sh     # 或 module load kml
# 生产脚本推荐手工版（可预期、不依赖 module 系统）：
K=/opt/HPCKit/26.0.RC1/kml/gcc; G=/opt/HPCKit/26.0.RC1/compiler/gcc
export LD_LIBRARY_PATH=$K/lib:$K/lib/noarch:$K/lib/sve512:$K/lib/matrix/kblas/multi:$G/lib64:$LD_LIBRARY_PATH
export CPATH=$K/include:$CPATH
```

要点：
- `sve512` 里**没有 kblas** → KBLAS 必须从 `matrix`/`sme`（0xd22）或 `neon`/`sve` 取。
- 必须带上 HPCKit gcc 的 `lib64`，否则 `undefined reference to omp_get_supported_active_levels@OMP_5.0.1`（KML 要 OMP 5.0.1 的 libgomp，系统 libgomp 太老）。
- **26.1.RC1 已把 `sme` 目录改名为 `matrix`**；写脚本别硬编码旧名，先 `ls $K/lib` 探测。
- 本机 `25.1.0`/`26.0.RC1` 的 `kml/gcc/lib` **没有 matrix 目录**（只有 sme）——回答此类问题时要说明版本差异。

## 3. ★ 向量长度（VL）约束：不匹配就「静默算错」，绝不报错

每个变体都是按**固定向量长度**编译的（SVE 256bit / SVE 512bit / SME 512bit 假设），
运行时 per-thread VL 不等于该假设 → 结果错误但不崩溃。实测（整数精确 GEMM + dgesv，结果均已逐元素校验）：

| 库 | 运行条件 | 实测结果 |
|---|---|---|
| `matrix`/`sme` KBLAS | 默认 `SME VL=256bit`（内核 `abi.sme_default_vector_length=32`） | n=256 dgemm **65518/65536 元素错** |
| `matrix`/`sme` KBLAS | 每线程 `prctl(PR_SME_SET_VL,64)`（512bit） | **0 错**（OMP=1/4/8 均 0） |
| `sve512` KLAPACK | 默认 SVL=256 / SVL=512 | 残差 5.5e-2 / **3.55e-15** |
| `sve/` 版 KLAPACK、KFFT | SVE VL=512（本机默认） | 垃圾值（1.6e+223）/ FFT 误差 1e+15；**把 SVL 设成 256bit 就全对** |
| `sve` KBLAS、`neon` 全部 | 任意 VL | 正确（sve 版 kblas 内部按 256bit 假设但实测对 512bit 机器也能过） |

**修法（已实测有效）**：VL 是 **per-thread** 的，`prctl` 只作用于当前线程，OpenMP worker 不继承 →
必须主线程设一次 + 每个线程再设一次（MPI 程序每个 rank、每个线程都要）：

```c
#include <sys/prctl.h>
#ifndef PR_SME_SET_VL
#define PR_SME_SET_VL 63            /* 老内核头文件没有；值 63 */
#endif
prctl(PR_SME_SET_VL, 64);           /* 64 字节 = 512bit */
#pragma omp parallel
{ prctl(PR_SME_SET_VL, 64); }       /* 让线程池里每个 worker 也进入 512bit */
```

- 只设主线程 → OMP=2 错一半、OMP=4 错 3/4（worker 仍用 256bit）。
- 系统级做法：`echo 64 > /proc/sys/abi/sme_default_vector_length`（永久影响全机新线程，须先在测试节点验证；不要擅自在用户机器上改）。
- 查实际值：`prctl(PR_SVE_GET_VL)` / `prctl(PR_SME_GET_VL)` 返回**字节数**；`cat /proc/sys/abi/{sve,sme}_default_vector_length`。
  本机 SVE=64B(512bit) 而 SME=32B(256bit) —— 两者可能不同，别混用。
- **验证手法**：用整数构造的矩阵做 GEMM（结果必为精确整数，任何偏差都是库/内核 bug 而非舍入），
  逐元素比对而不只看 sum/C00。比看相对误差快得多。

## 4. 链接与装载坑

- `libklapack.so` **没有 SONAME**，且拆分版缺 netlib 参考实现符号 → 用 `libklapack_full.so`（其 BLAS 符号是 U，运行期再从 libkblas 解析），链接要 `-lklapack_full -lkblas`。
- 多个 ISA 目录同时在 `LD_LIBRARY_PATH` 时**按目录顺序取第一个同名库**；根 `lib/libklapack_full.so` 实测就是 sve512 版拷贝（时间戳比安装时间新、比 `sve512/` 版大 192B），极易被误加载。→ 把想要的变体目录放最前。
- `dladdr()` 对导入符号常返回可执行文件自身的 PLT 地址，**不能用来确认加载了哪个变体**；要确认请读 `/proc/self/maps` 或 `LD_DEBUG=libs`。
- KML 库初始化会向 **stdout** 打 `Warning: libsdma_dk.so ... not found`（污染 meson `run_command`），见 `kml-stdout-warning-pollution.md`。

## 5. 编译/运行模板（实测通过）

```bash
GCC=/opt/HPCKit/26.0.RC1/compiler/gcc/bin/gcc; K=/opt/HPCKit/26.0.RC1/kml/gcc
G64=/opt/HPCKit/26.0.RC1/compiler/gcc/lib64
L=$K/lib:$K/lib/noarch:$K/lib/sve512:$K/lib/matrix/kblas/multi:$G64

# BLAS
$GCC -O2 -fopenmp -I$K/include app.c -o app -L$K/lib/matrix/kblas/multi -L$G64 -lkblas -lgomp -ldl -lm
# LAPACK
$GCC -O2 -fopenmp -I$K/include app.c -o app -L$K/lib/sve512 -L$K/lib/matrix/kblas/multi -L$G64 \
     -lklapack_full -lkblas -lgomp -lstdc++ -lm -ldl
# FFT（FFTW3 兼容接口 -lfftw3 亦可走原生 kfft.h）
$GCC -O2 -fopenmp -I$K/include app.c -o app -L$K/lib/noarch -L$K/lib/sve512 -L$G64 -lfftw3 -lkfft -lgomp -lm

KML_SME_VL=64 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$L ./app
```

## 6. 反汇编判据（不靠目录名判断变体）

```bash
objdump -d --no-show-raw-insn <lib> | awk '/fmmla/{f64++} /ld1ro/{ro++} /fmopa/{sme++} /z[0-9]+\./{sve++} /v[0-9]+\./{neon++} END{print "f64mm="f64, "sme="sme, "sve="sve, "neon="neon}'
readelf -d <lib> | grep NEEDED
```
- `fmmla` / `ld1ro[bhwd]` ⇒ F64MM（sve 完整版有，`sve_no_f64mm` 无）
- `fmopa` / `fmops` ⇒ SME 矩阵扩展（`matrix`/`sme` 变体独有）
- SVE 用 `z` 寄存器，NEON 用 `v` 寄存器；`movprfx`/`addvl` 也是 SVE 特征
- 实测参照：`neon/kblas` 只有 v 寄存器、零 SVE；`sve/kblas` 有 ~939 万条 z 寄存器 + 34.5 万条 FP16 `fmlal`；`sme/kblas` 有 ~38.1 万条 `fmopa`

## 7. 实测性能（n=2048, taskset 0-3, VL 已正确设置, 结果已校验）

| KBLAS 变体 | dgemm GFLOP/s (OMP=1/4) | sgemm GFLOP/s (OMP=1/4) |
|---|---|---|
| `matrix`/`sme` | 148 / **510~520** | 300 / **1004~1021** |
| `sve` | – / 157~174 | – / 363~389 |
| `neon` | – / 54~57 | – / 120 |

KFFT 1M 点复数：sve512 0.024 s、neon 0.029 s。→ 0xd22 上 KBLAS 必须用 `matrix`/`sme`（约 `sve` 的 3 倍、`neon` 的 9 倍）。

## 8. 与 spack 包的关系

spack 侧的 `kpblas` 会按 `/proc/cpuinfo` 自动检测 neon/sve/sme 子目录（见 `kpkml` 的 `setup_dependent_build_environment`）。
本节内容用于**手工编译/调试应用**（不在 spack 环境里）时选对目录、并避开 VL 陷阱。
