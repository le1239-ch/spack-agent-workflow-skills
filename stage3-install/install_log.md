# Stage3 安装日志

> 清单来源：`/home/zhangyuhang/workflow/stage2-packages/packages_to_install.yaml`（md5 `41738466a8132dc94937132cafde31cf`）
> 本轮清单：fds,6.9.1,both / su2,7.5.1,both / cmaq,5.3,both / swan,4145,both / roms,4.2,both → 5 包 × 2 编译器 = **10 个安装任务**
> 编译器映射：清单 `bisheng` → spack `%llvm`（BiSheng 注册名）；`both` → `%gcc` + `%llvm` 两次安装
> 执行方式：按 AI_INSTRUCTION 决策树逐个执行 spack 命令（未直接运行 install_batch.sh）
> 执行窗口：2026-10-09 14:20–15:50 CST；机器空闲（608 核，load ~2），作业与另一用户（wuhuajian 的 ambertools）并行但无冲突

**结果：10/10 成功，无移交**（每个任务的状态见下表「状态」列）。

| 包名 | 编译器 | 版本 | hash | 状态 | 方式 | 重试次数 | 备注 |
|------|--------|------|------|------|------|---------|------|
| fds | gcc | 6.9.1 | 2jvgrgl | ✅ 成功 | package.py modified（本地 repo，A2） | 1 | 挑战1=去 x86/Intel 绑定（`depends_on("mkl")` + 3 条 `requires`）并去掉 aarch64 gfortran 不认的 `-m64`。产物 `bin/fds`（ELF aarch64，NEEDED `libmpi.so.40`），实跑无参打印 FDS banner |
| fds | bisheng | 6.9.1 | wvwdedm | ✅ 成功 | package.py modified（本地 repo，A2） | 2 | 挑战2=`IMPLICIT NONE (TYPE,EXTERNAL)`（F2018）→ BiSheng 的 Fortran 前端是 classic Flang 1.5（F2003），49 处需降级为 `IMPLICIT NONE`；挑战3=hmpi 用 gcc 变体→`mpi.mod` 与 flang 不兼容，改 `^hmpi compiler_variant=bisheng`；新增 `ompi_flang_linux` make 目标 |
| su2 | gcc | 7.5.1 | z6rrgml | ✅ 成功 | builtin（+ 依赖修复） | 2 | 原生 recipe 可解析；阻塞在依赖链 `py-scipy`（kp repo 包缺陷，见下）。修复后一次过；`~mpi` 故无 MPI NEEDED |
| su2 | bisheng | 7.5.1 | 3cjzmva | ✅ 成功 | builtin（+ 依赖修复） | 2 | 同上；另加 `-Dc_std=none`（spack 编译器 wrapper 下 meson 的 c17 能力探测失败） |
| cmaq | gcc | 5.3.1（清单写 5.3） | mznbwiz | ✅ 成功 | builtin | 0 | ⚠ 该 spack 包**只解包源码**（`install_tree(".", prefix)`），不编译 → prefix 下无二进制。真正出可执行文件仍需 `CCTM/scripts/bldit_cctm.csh`。清单 `5.3` 是版本范围 → 实际 concretize 成 `5.3.1` |
| cmaq | bisheng | 5.3.1（清单写 5.3） | 4ekbrka | ✅ 成功 | builtin | 0 | 同上（源码分发包，两编译器产物一致） |
| swan | gcc | 4145 | wlwzozz | ✅ 成功 | package.py modified（本地 repo，A2） | 1 | 挑战1=SWAN 的 `platform.pl` 只在 `if ($ver =~ /10/i)` 时加 `-fallow-argument-mismatch`，gcc 12.3.1 不匹配 → `Type mismatch between actual argument` 硬错。改为 gcc≥10 一律加 |
| swan | bisheng | 4145 | yjxoulh | ✅ 成功 | package.py modified（本地 repo，A2） | 3 | 挑战2=`platform.pl` 白名单无 flang → `Current Fortran compiler 'flang' not supported`，加 flang 分支；挑战3=classic flang 按 132 列读固定格式 → SWAN `.f` 行尾修订号（>72 列）被当代码 → 加 `-ffixed-line-length-72`；挑战4=`hcat` 子目标用 `F90_SER=gfortran` 而 gcc 不在 flang 的 DAG 里 → `F90_SER/F90_OMP=flang`。另需 `^netcdf-fortran %llvm ^hmpi compiler_variant=bisheng`（跨编译器 .mod） |
| roms | gcc | 4.2 | xq4bdvx | ✅ 成功 | builtin | 0 | 直接成功（ROMS 4.2 的 `-fallow-argument-mismatch` 修补只针对 `@:4.0`，4.2 无需） |
| roms | bisheng | 4.2 | ahn6fxj | ✅ 成功 | package.py modified（本地 repo，A2） | 2 | 挑战1=ROMS 无 `Compilers/Linux-flang.mk`（recipe 把 `FORT=flang`），include 失败导致 `TEST/MKDIR/CP/FC` 全空 → `/bin/sh: -d: invalid option`、`MakeDepend: Not a directory` 级联错。补出该文件（从 `Linux-gfortran.mk` 派生，去掉 gfortran 专有项）；挑战2=flang 腿的 `hdf5+fortran` 在 CMake `FindMPI` 下报 `Could NOT find MPI (missing: MPI_Fortran_FOUND)`（HPCKit 的 hmpi 没有 `mpi.mod`，只有 `mpif.h`）→ flang 腿改用 `hdf5~fortran`（ROMS 的 makefile 从不设 `USE_HDF5`，不用 HDF5 Fortran 绑定） |

## 证据（全部实测，非脚本自述）

- **架构**：8 个产物二进制 `file` 均为 `ELF 64-bit LSB executable, ARM aarch64`。
- **依赖链接**：`readelf -d` NEEDED 实测
  - fds gcc/llvm、swan gcc/llvm、roms gcc/llvm → 均含 `libmpi.so.40`（+`libmpi_mpifh.so.40`/`libmpi_usempif08.so.40`）；swan/roms 另含 `libnetcdff.so.7` → 走 hmpi + netcdf-fortran，非回落系统库。
  - su2 两条腿 → `~mpi`（清单未要求 MPI），无 MPI NEEDED，符合 spec。
- **冒烟**：`fds`（无参）打印 `Fire Dynamics Simulator / Current Date ... / Revision -HEAD`；`SU2_CFD`（无参）正确报 `The configuration file (.cfg) is missing!!`（用法提示，非崩溃）。
- **cmaq**：prefix 下只有源码树（`CCTM/`、`PREP/`、`POST/`、`UTIL/`、`DOCS/`、`bldit_project.csh`、`config_cmaq.csh`），无 `.exe`/ELF —— 与 recipe 语义一致（见上表备注）。

## 本轮改动的文件（含回滚方式）

### 本地 repo（`kunpeng920F-repo/spack_repo/kunpeng920f_workflow/packages/`，stage3 的合法产出）

| 包 | 文件 | 要点 | 原始（builtin）副本 |
|----|------|------|--------------------|
| fds | `fds/package.py` | 去 MKL/Intel `requires`；`-m64` 过滤；flang 目标 + `IMPLICIT NONE` 降级；`parallel=False` | `fds/package.py.builtin-orig` |
| swan | `swan/package.py` | `platform.pl` 补 gcc≥10 与 flang 分支（含 `-ffixed-line-length-72`、`F90_SER/F90_OMP=flang`） | `swan/package.py.builtin-orig` |
| roms | `roms/package.py` | 生成 `Compilers/Linux-flang.mk`；flang 腿 `hdf5~fortran` | `roms/package.py.builtin-orig` |

未修改 `kunpeng920prof`（kp repo）中的 kp*/hmpi 任何包，未修改 builtin 原始 recipe。

### 用户代码（kp repo，已获用户明确同意后修改）

`kunpeng920prof/spack_repo/kunpeng920prof/packages/py_scipy/package.py`（md5 原 `2feba18c180a60ef7a346dd7cce3d1ca`）

1. numpy include 路径：`numpy/core/include` 写死 → numpy 2.x 已改名 `numpy/_core/include`；改为探测 `_core`/`core` × `lib`/`lib64`。
2. `-Dblas=kblas -Dlapack=klapack_full` → `-Dblas=openblas -Dlapack=openblas`：**KML（kpblas@26.0.RC1 与系统 HPCKit 25.1.0）不提供任何 `.pc`/`.cmake` 配置**，scipy meson 的 `dependency('kblas')` 永远无法解析（实测 `Dependency "kblas" not found`）。
3. `%llvm` 腿追加 `-Dc_std=none`（wrapper 下 c17 探测失败）。
4. 新增 `depends_on("openblas")`，让 `openblas.pc` 进入 scipy 的构建环境。

> 备份：`stage3-install/.code-backup-20261009-150312/home/zhangyuhang/...`
> 回滚：`cp -a <该备份>/home/zhangyuhang/.../py_scipy/package.py <kp repo 对应路径>`
> 已按用户指令（2026-10-09）执行；scipy 由 KML 链接改为 OpenBLAS 链接属用户确认过的取舍。

### 配置漂移：**零**

`$ETC/{config,repos,packages}.yaml`、`$ETC/site/packages.yaml`、`user-config/{packages,repos}.yaml` 与运行前备份 `.config-backup-20261009-142013/` **逐字节一致**（`diff -q` 全部 IDENTICAL）。

### 指令文件：**未改**

`AI_INSTRUCTION.md` md5 `7657a7006ac7435f1f789e30821f035d`、`DESCRIPTION.md` md5 `be6e8d071087e6db783b2eee8e5209ef`，执行前后一致。

## 与清单/阶段2结论的差异

- `cmaq,5.3` → 实际 `5.3.1`（`@X.Y` 是版本范围，阶段2 已提示）。
- 阶段2 判定 fds「aarch64 无解，需阶段3 自写 package.py」→ **已完成**，两条腿都装出来了。
- 阶段2 判定 su2/cmaq/swan/roms「走常规 `spack install`」→ 实测：su2/swan/roms 的 **%llvm 腿**、swan 的 %gcc 腿都必须改 recipe（fds 两条腿都改）；仅 cmaq 和 roms %gcc 是纯 builtin 直接成功。

## 后续（stage4 提示）

- fds/swan/roms 的 %llvm 腿依赖 **BiSheng = classic Flang 1.5（F2003）前端**，编译通过是靠针对性适配；stage4 做 SVE/编译优化时注意 `%llvm` 端的 flang 不仅不支持 F2018，也不认 `-fallow-argument-mismatch`。
- swan/roms 的 %llvm 腿用了 `^hmpi compiler_variant=bisheng` + `^netcdf-fortran %llvm`，不是默认 provider（默认 hmpi 是 gcc 变体）——重装/重具体化时须带同样的约束，否则会回到跨编译器 `.mod` 不兼容。
- HPCKit 的 hmpi 两个变体都**没有 `mpi.mod`**（只有 `mpif.h`），任何用 `use mpi` 的 Fortran 代码/CMake `FindMPI` Fortran 探测都会失败。
