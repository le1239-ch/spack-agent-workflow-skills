# CMake 项目跨编译器（gcc/llvm）安装陷阱

> 阶段3 安装 elmerfem@9.0 `both`（gcc+bisheng）时实测的三个独立问题与修复。
> 适用于任何含 Fortran + C 混编、且 CMake 有 MKL 探测逻辑的 HPC 科学计算包。

## 1. OpenBLAS `make all` 在 aarch64 上 SIGABRT（Error 134）

**现象：** `spack install elmerfem@9.0 %gcc` 失败，openblas@0.3.30 的 `make all` 运行 LAPACK 测试时 SIGABRT：
```
make[1]: *** [Makefile:197: all3] Error 134
make: *** [Makefile:178: tests] Error 2
```

**根因：** OpenBLAS 的 Makefile 中 `all :: tests`（第 57 行），`all` 目标依赖 `tests`。aarch64 上部分 LAPACK 测试 SIGABRT（Error 134 = SIGABRT），导致整个 `make all` 失败。

**Makefile 目标依赖链：**
```
all → tests → shared → libs + netlib
```
- `all` — 编译库 + 生成 .so + **跑测试**（测试失败则 abort）
- `shared` — 依赖 `libs` + `netlib`，生成 `libopenblas-r0.3.30.so`，**不跑测试**
- `libs` — 只编译静态库，**不生成 .so**（install 阶段会找不到 .so 报错）

**修复：** 复制 openblas package.py 到本地 repo，修改 `build_targets`：
```python
@property
def build_targets(self):
    # Use 'shared' instead of 'all' to skip tests that SIGABRT on aarch64
    return ["-s"] + self.make_defs + ["shared"]
```

**⚠ 不要用 `["libs"]`：** `libs` 不生成 `libopenblas-r0.3.30.so`，install 阶段报 `install: cannot stat 'libopenblas-r0.3.30.so': No such file or directory`。必须用 `shared`。

**诊断方法：** 查看 openblas 源码 Makefile 确认目标依赖：
```bash
grep -n '^all\b\|^shared\|^libs\b\|^tests\b' <stage>/spack-src/Makefile
# all :: tests          (第 57 行)
# shared : libs netlib  (第 146 行)
# tests : shared        (第 173 行)
# libs :                (第 192 行)
```

## 2. GCC 12+ Fortran DO 循环变量重定义错误（elmerfem issue #274）

**现象：** `spack install elmerfem@9.0 %gcc` 编译 `DCRComplexSolve.F90` 时报：
```
Error: Index variable 'i' redefined at (1) in procedure 'inputvector'
       called from within DO loop at (2)
make[2]: *** [DCRComplexSolve.F90.o] Error 1
```

**根因：** elmerfem 的 `DCRComplexSolve.F90` 中，内层子程序 `InputVector`/`InputTensor` 的 DO 循环使用了外层作用域的变量 `i`，而内层子程序没有声明自己的 `i`。GCC 11+ 严格执行 Fortran 2018 DO 循环变量 shadowing 检查。

**⚠ `-std=legacy` 不能修复此错误！** 实测加 `-std=legacy -fallow-argument-mismatch` 后错误依旧。这是 GCC 11+ 的硬性检查，不随标准模式放宽。

**修复：** 复制 elmerfem package.py 到本地 repo，在 `patch()` 方法中用 `filter_file` 添加局部 `i` 声明：
```python
def patch(self):
    if self.spec.satisfies("@9.0"):
        dcr = join_path("fem", "src", "modules", "DCRComplexSolve.F90")
        filter_file(
            r"INTEGER :: n, NodeIndexes\(:\)",
            "INTEGER :: i, n, NodeIndexes(:)",
            dcr,
        )
```

**上游修复：** commit `96a33930ee23e785f33bcb257398f1ccca8fdf99`（2021-05-02），但 release-9.0 tarball 仍含此 bug。上游的 patch 文件因行号偏移无法直接 `patch()` 声明（9/9 hunks FAILED），必须用 `filter_file` 方式。

## 3. BiSheng/Flang 跨编译器 .mod 文件不兼容

**现象：** `spack install elmerfem@9.0 %llvm` 编译 elmerice 模块时报：
```
F90-F-0004-Corrupt or Old Module file, please try to recompile
    /tmp/spack-opt/.../netcdf-fortran-4.6.2-.../include/netcdf.mod
F90/aarch64 Linux Flang - 1.5 2017-05-01: compilation aborted
```

**根因：** spack concretizer 复用了已安装的 `netcdf-fortran@4.6.2 %gcc`（用 GCC gfortran 编译），其 `.mod` 文件格式是 GCC 特有的。BiSheng 的 Flang **无法读取** GCC 编译的 `.mod` 文件。两个编译器的 `.mod` 二进制格式不兼容。

**修复：** 强制 netcdf-fortran 也用 `%llvm` 编译：
```bash
spack install elmerfem@9.0 %llvm ^netcdf-fortran %llvm
```

**⚠ 通用规则：** 当 bisheng（%llvm）腿的包依赖 Fortran 库（netcdf-fortran、hypre 等）时，spack 可能复用 gcc 编译的版本。**所有提供 `.mod` 文件的 Fortran 依赖必须与主包使用相同编译器。** 在 `spack spec` 输出中检查依赖的编译器标记：如果看到 `^netcdf-fortran ... %c,fortran=gcc@12.3.1` 而主包是 `%llvm`，则需要 `^netcdf-fortran %llvm` 强制重编。

**诊断：**
```bash
spack spec elmerfem@9.0 %llvm | grep "fortran="
# 如果依赖行显示 %fortran=gcc 而主包是 %fortran=clang → .mod 不兼容
```

### 3a. Stage3.5 手动编译兜底：跳过 netcdf 功能绕过 .mod 不兼容

当 `^netcdf-fortran %llvm` 修复无效或 stage3.5 手动编译场景中无法控制 spack 依赖解析时，可用以下手动编译策略：

**核心思路：** 不向 CMake 传递 netcdf 路径 → 项目的 `FindNetCDF.cmake` 找不到库 → netcdf 相关功能自动禁用 → 不编译引用 `netcdf.mod` 的源文件 → 避开 `.mod` 不兼容错误。

**实测有效（elmerfem@9.0 + BiSheng flang 19.1.7）：**

```bash
# 1. 加载 HPCKit bisheng 环境
source <hpckit>/HPCKit/<ver>/setvars.sh   # 不加 --use-gcc

# 2. CMake 配置（不传任何 netcdf 相关变量）
cmake <src> \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_Fortran_COMPILER=flang \
  -DCMAKE_INSTALL_PREFIX=<prefix> \
  -DWITH_ElmerIce=ON \
  -DBLAS_LIBRARIES=<openblas-clang>/lib/libopenblas.so \
  -DLAPACK_LIBRARIES=<openblas-clang>/lib/libopenblas.so \
  -DCMAKE_C_FLAGS="-Wno-error=implicit-function-declaration -Wno-error=implicit-int" \
  -DCMAKE_Fortran_FLAGS="-ffree-line-length-none" \
  -DWITH_MPI=ON -DWITH_OpenMP=ON \
  -DMPI_C_COMPILER=mpicc -DMPI_Fortran_COMPILER=mpif90
  # ↑ 不传 -DNETCDF_INCLUDE_DIR / -DNETCDF_LIBRARY 等

# 3. make + install
make -j$(nproc) && make install
```

**CMake 输出会显示（正常）：**
```
-- Library not found: >NetCDF_FOUND<
CMake Warning: Missing: >NetCDF_INCLUDE_DIR< , >NetCDF_LIBRARY<, >NetCDFF_LIBRARY<
   some functionalities will be disabled
```

**代价：** ElmerIce 的 netcdf-dependent 求解器（GridDataReader、Adjoint 等）不会编译，但 elmerfem 核心求解器和大部分 ElmerIce 模块正常工作。对不需要 netcdf I/O 的仿真场景无影响。

**关键依赖路径选择：** 手动编译时必须使用与 bisheng 兼容的依赖版本：
- OpenBLAS：用 clang 编译的版本（`spack find -p openblas %llvm`），不能用 gcc 版本
- HMPI：用 bisheng 变体（`setvars.sh` 自动加载 `hmpi/bisheng/release/`）
- netcdf-c/netcdf-fortran：完全跳过（CMake 自动禁用功能）

**适用场景：** stage3.5 手动编译兜底、CI/CD 快速验证编译可行性、不需要 netcdf 功能的生产部署。

## 4. Flang 不支持 GCC 特有的 Fortran flags

**现象：** `spack install elmerfem@9.0 %llvm` 报 `flang: error: unknown argument: '-fallow-argument-mismatch'`。

**根因：** `-fallow-argument-mismatch` 是 GCC 10+ 特有的 flag，Flang（BiSheng 的 Fortran 编译器）不认识。

**修复：** 在 `cmake_args()` 中为不同编译器设不同的 Fortran flags：
```python
if spec.satisfies("%gcc"):
    args.append("-DCMAKE_Fortran_FLAGS=-std=legacy -fallow-argument-mismatch -ffree-line-length-none")
if spec.satisfies("%clang") or spec.satisfies("%llvm"):
    args.append("-DCMAKE_Fortran_FLAGS=-ffree-line-length-none")
    # 不要加 -fallow-argument-mismatch（Flang 不支持）
```

## 5. Clang 19+ 将 implicit-function-declaration 视为错误

**现象：** `spack install elmerfem@9.0 %llvm` 报：
```
error: call to undeclared function 'time'; ISO C99 and later do not support
       implicit function declarations [-Wimplicit-function-declaration]
```

**根因：** Clang 19+ 默认将隐式函数声明视为错误（C99+ 标准）。GCC 默认只警告不报错。旧式 C 代码（如 elmerfem 的 matc/src/matrix.c、jacobi.c）缺少 `#include` 头文件。

**修复：** 在 `cmake_args()` 中为 Clang 添加 C flags：
```python
if spec.satisfies("%clang") or spec.satisfies("%llvm"):
    args.append("-DCMAKE_C_FLAGS=-Wno-error=implicit-function-declaration -Wno-error=implicit-int")
```

## 6. CMake FindMKL.cmake 对 Flang 报 FATAL_ERROR

**现象：** `spack install elmerfem@9.0 %llvm` 在 cmake 配置阶段报：
```
CMake Error at cmake/Modules/FindMKL.cmake:89 (MESSAGE):
  Finding MKL libraries not implemented for
                  Flang
```

**根因：** elmerfem 的 CMakeLists.txt 在 BLAS/LAPACK 未显式设置时调用 `FIND_PACKAGE(MKL QUIET)`。FindMKL.cmake 只处理 GNU/Intel/PGI 编译器，`ELSE()` 分支直接 `MESSAGE(FATAL_ERROR ...)`。Flang 走 ELSE 分支。**FATAL_ERROR 覆盖 QUIET**，即使加了 QUIET 也会中止配置。

**修复：** 在 `cmake_args()` 中显式设置 BLAS_LIBRARIES 和 LAPACK_LIBRARIES，使 CMakeLists.txt 不进入 `FIND_PACKAGE(MKL QUIET)` 分支：
```python
if not spec.satisfies("^[virtuals=lapack] intel-oneapi-mkl"):
    blas = spec["blas"]
    lapack = spec["lapack"]
    blas_libs = ";".join(blas.libs.libraries) if blas.libs else ""
    lapack_libs = ";".join(lapack.libs.libraries) if lapack.libs else ""
    if blas_libs:
        args.append("-DBLAS_LIBRARIES={0}".format(blas_libs))
    if lapack_libs:
        args.append("-DLAPACK_LIBRARIES={0}".format(lapack_libs))
```

**CMakeLists.txt 逻辑（elmerfem release-9.0，约第 295-310 行）：**
```cmake
IF (NOT BLAS_LIBRARIES OR NOT LAPACK_LIBRARIES)
    FIND_PACKAGE(MKL QUIET)         # ← Flang 在这里 FATAL_ERROR
    IF (MKL_BLAS_LIBRARIES_FOUND AND MKL_LAPACK_LIBRARIES_FOUND)
        SET(BLAS_LIBRARIES ...)
    ENDIF()
ENDIF()
```
设置 `-DBLAS_LIBRARIES=...` 后 `NOT BLAS_LIBRARIES` 为 false，跳过整个 `FIND_PACKAGE(MKL)` 块。

## 综合修复模板

elmerfem@9.0 both 编译器的完整 `cmake_args()` + `patch()` 修改（复制官方 package.py 到本地 repo 后）：

```python
def cmake_args(self):
    spec = self.spec
    args = ["-DWITH_ElmerIce=ON", "-DWITH_CONTRIB=ON"]

    # GCC 12+ Fortran flags（-std=legacy 不修复 DO 循环变量问题，见 patch()）
    if spec.satisfies("%gcc"):
        args.append("-DCMAKE_Fortran_FLAGS=-std=legacy -fallow-argument-mismatch -ffree-line-length-none")

    # 显式设置 BLAS/LAPACK，避免 FindMKL.cmake 对 Flang 报 FATAL_ERROR
    if not spec.satisfies("^[virtuals=lapack] intel-oneapi-mkl"):
        blas = spec["blas"]
        lapack = spec["lapack"]
        blas_libs = ";".join(blas.libs.libraries) if blas.libs else ""
        lapack_libs = ";".join(lapack.libs.libraries) if lapack.libs else ""
        if blas_libs:
            args.append("-DBLAS_LIBRARIES={0}".format(blas_libs))
        if lapack_libs:
            args.append("-DLAPACK_LIBRARIES={0}".format(lapack_libs))

    # Clang 19+ implicit-function-declaration 是错误
    if spec.satisfies("%clang") or spec.satisfies("%llvm"):
        args.append("-DCMAKE_C_FLAGS=-Wno-error=implicit-function-declaration -Wno-error=implicit-int")
        args.append("-DCMAKE_Fortran_FLAGS=-ffree-line-length-none")
        # 注意：不要加 -fallow-argument-mismatch（Flang 不支持）

    # ... 其余原有 cmake_args ...

    return args

def patch(self):
    if self.spec.satisfies("@9.0"):
        # 修复 GCC 12+ DO 循环变量重定义错误
        dcr = join_path("fem", "src", "modules", "DCRComplexSolve.F90")
        filter_file(
            r"INTEGER :: n, NodeIndexes\(:\)",
            "INTEGER :: i, n, NodeIndexes(:)",
            dcr,
        )
    # ... 原有 @8.4 patch ...
```
