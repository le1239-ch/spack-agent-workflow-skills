# hmpi OMPI_CC 注入缺失：调试与 A/B 对照实验

## 问题概述

hmpi 是 HPCKit 的 MPI wrapper 包（`has_code=False`），其 `setup_dependent_build_environment` 只设置了 `OPAL_PREFIX`，**没有设置 `OMPI_CC`/`OMPI_CXX`/`OMPI_FC`/`OMPI_F77`**。

标准 openmpi 的 spack package.py 会设置这些变量，让 mpicc（opal_wrapper 二进制）改用 spack 编译器 wrapper（`spack_cc`），而非 wrapper-data.txt 中写死的裸 `gcc`/`clang`。

### 根本机制

```
mpicc hello.c
    ↓
opal_wrapper 读取 wrapper-data.txt
    ↓
取 compiler=gcc（或 clang）          ← 写死的裸编译器
    ↓
组装命令：gcc -I... -L... -lmpi hello.c
    ↓
实际执行这个命令                      ← 不经过 spack wrapper
```

设置 `OMPI_CC=spack_cc` 后：
```
mpicc hello.c
    ↓
opal_wrapper 读取 wrapper-data.txt（取 -I/-L/-lmpi 等链接参数）
    ↓
发现 OMPI_CC 环境变量 → 用 spack_cc 代替裸 gcc   ← OMPI_CC 覆盖
    ↓
spack_cc 内部：gcc + rpath注入 + 运行时库路径 + 编译器标志
    ↓
最终执行：gcc -Wl,-rpath,/spack/.../hmpi/lib -I... -L... -lmpi hello.c
```

## 诊断方法

### 1. 检查 mpicc --show 的编译器

```bash
# 在 spack 构建环境中
spack build-env <pkg> %gcc -- bash -c 'mpicc --show | awk "{print \$1}"'
# 输出裸 "gcc" → OMPI_CC 未注入（有问题）
# 输出 spack wrapper 路径 → OMPI_CC 已注入（正确）
```

### 2. 检查 hmpi 库编译器版本

```bash
# 从 hmpi 的 libmpi.so 提取编译器版本
strings <hmpi_prefix>/lib/libmpi.so | grep -oE "GCC:.*" | head -1
```

### 3. strace 追踪 opal_wrapper 读哪个 wrapper-data.txt

```bash
strace -f -e trace=openat <hmpi_prefix>/bin/mpicc --show 2>&1 | grep wrapper-data
# 如果读 /usr/lib64/openmpi/... → 指向系统 openmpi（错误）
# 如果读 <hmpi_prefix>/share/openmpi/... → 指向 hmpi（正确）
```

注意：opal_wrapper 读取的 wrapper-data.txt 路径由其链接的 `libopen-pal.so` 的 installdirs 决定。如果 `LD_LIBRARY_PATH` 优先加载了系统 `/usr/lib64/openmpi/lib/libopen-pal.so`，opal_wrapper 会读系统路径的 wrapper-data.txt，完全绕过 hmpi。

## A/B 对照实验复现步骤

### 前置：找到路径

```bash
source /home/wuhuajian/spack-1.1.1/share/spack/setup-env.sh

# hmpi prefix（gcc 变体）
HMPI=$(spack find -p hmpi compiler_variant=gcc 2>&1 | grep "hmpi@26.0.RC1" | head -1 | awk '{print $NF}')/HPCKit/26.0.RC1/hmpi/gcc/release/hmpi

# hpckit gcc 12.3.1
GCC=$(spack compiler info gcc@12.3.1 2>&1 | grep "cc:" | head -1 | awk '{print $2}')

# gcc-runtime spack 包
GCCRT=$(spack find -p gcc-runtime@12.3.1 2>&1 | head -1 | awk '{print $NF}')
```

### A 组：不设 OMPI_CC（当前 hmpi package.py 行为）

```bash
# mpicc --show 输出的编译器
OPAL_PREFIX=$HMPI LD_LIBRARY_PATH=$HMPI/lib PATH=$HMPI/bin:$PATH \
  $HMPI/bin/mpicc --show 2>&1 | awk '{print $1}'
# 输出: gcc （系统 PATH 中的裸 gcc）

# 系统 gcc 版本
gcc --version | head -1
# 输出: gcc (GCC) 10.3.1
```

### B 组：设 OMPI_CC=hpckit gcc（模拟修复后行为）

```bash
# mpicc --show 输出的编译器
OMPI_CC=$GCC OPAL_PREFIX=$HMPI LD_LIBRARY_PATH=$HMPI/lib PATH=$HMPI/bin:$PATH \
  $HMPI/bin/mpicc --show 2>&1 | awk '{print $1}'
# 输出: /home/wuhuajian/.../compiler/gcc/bin/gcc （OMPI_CC 指定的路径）

# hpckit gcc 版本
$GCC --version | head -1
# 输出: gcc (gcc for openEuler 3.0.3) 12.3.1
```

### 对比：hmpi libmpi.so 编译器版本

```bash
strings $HMPI/lib/libmpi.so | grep -oE "GCC:.*" | head -1
# 输出: GCC: (gcc for openEuler 3.0.3) 12.3.1
```

### 结论

| | A 组（无 OMPI_CC） | B 组（有 OMPI_CC） | hmpi 库 |
|---|---|---|---|
| mpicc 调用的编译器 | 系统 gcc 10.3.1 | hpckit gcc 12.3.1 | gcc 12.3.1 |
| 版本匹配？ | ❌ 不匹配 | ✅ 匹配 | — |

版本不匹配的风险：
- `libstdc++.so.6` CXXABI 版本不同（10.3.1 最高 CXXABI_15, 12.3.1 最高 CXXABI_17）
- 如果 hmpi 的 C++ 组件用 12.3.1 编译而程序用 10.3.1 链接，可能运行时崩溃

## 在真实 spack 构建环境中验证

```bash
# 获取 osu-micro-benchmarks 的完整构建环境
spack build-env osu-micro-benchmarks %gcc -- bash -c '
  echo "SPACK_CC=$CC"          # spack compiler wrapper 路径
  echo "SPACK_CXX=$CXX"
  echo "OMPI_CC=$OMPI_CC"      # 应该是 spack_cc 但实际为空
  echo "OPAL_PREFIX=$OPAL_PREFIX"
  echo "MPICC=$MPICC"          # hmpi 的 mpicc 路径
  echo "which mpicc=$(which mpicc)"
'
```

预期输出：
```
SPACK_CC=/home/wuhuajian/.../compiler/gcc/bin/gcc
CC=/home/wuhuajian/.../compiler-wrapper-1.1.0-.../libexec/spack/gcc/gcc
OMPI_CC=                         ← 空！hmpi 没有设置
OPAL_PREFIX=/home/wuhuajian/.../hmpi/gcc/release/hmpi
MPICC=/home/wuhuajian/.../hmpi/gcc/release/hmpi/bin/mpicc
which mpicc=/home/wuhuajian/.../hmpi/gcc/release/hmpi/bin/mpicc
```

## 修复方案

在 hmpi 的 package.py 的 `setup_dependent_build_environment` 末尾添加：

```python
def setup_dependent_build_environment(self, env, dependent_spec):
    # ... 原有的 LD_LIBRARY_PATH / PATH / CPATH / OPAL_PREFIX 注入 ...

    # ★关键修复★ 注入 OMPI_CC / OMPI_CXX / OMPI_FC / OMPI_F77
    dependent_module = dependent_spec.package.module
    for var_name, attr_name in (
        ("OMPI_CC", "spack_cc"),
        ("OMPI_CXX", "spack_cxx"),
        ("OMPI_FC", "spack_fc"),
        ("OMPI_F77", "spack_f77"),
    ):
        if hasattr(dependent_module, attr_name):
            env.set(var_name, getattr(dependent_module, attr_name))
```

这与标准 openmpi package.py 的 `setup_dependent_build_environment` 完全一致。

## 相关源码位置

- hmpi package.py: `/home/wuhuajian/spack_repos/spack_repo/wuhuajian_repos/packages/hmpi/package.py`
- 标准 openmpi package.py: `<builtin>/packages/openmpi/package.py`（`setup_dependent_build_environment` 方法）
- hmpi wrapper-data.txt: `<hmpi_prefix>/share/openmpi/mpicc-wrapper-data.txt`
- hmpi opal_wrapper: `<hmpi_prefix>/bin/opal_wrapper`（mpicc 是其符号链接）
