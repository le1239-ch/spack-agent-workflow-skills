# 阶段2 包验证报告 (package_verification.md)

> 本文件由 stage2-packages 执行生成。
> 执行时间：2026-10-09（阶段1完成后，本轮清单）
> 验证方式：只读探针 `scripts/verify_packages.sh`（存在性 → 指定版本 → `spack spec` 双编译器 → provider 路由）；阶段2 **未执行任何 `spack install`**。

---

## 加载的 Skill

- **kerminal/kp-workflow-deploy**：workflow stage 执行指南（stage2 验证判据、探针脚本、`spack info` Safe versions 解析坑、`@X.Y` 版本范围坑）
- **kerminal/spack-new-package**：HPCKit 生态 spack 包知识库（阶段3 自写 package.py 时用；本阶段的 BiSheng=`%llvm` 映射与包名验证经验来自此）

---

## 环境

| 项 | 值 |
|---|---|
| 架构 | `aarch64` ✅ |
| spack | `1.2.1`（工作流独立实例：`/home/zhangyuhang/workflow/spack-workflow/spack-1.2.1`） |
| 环境入口 | `source /home/zhangyuhang/workflow/scripts/spack-env.sh`（裸 source，不带管道） |
| user scope 隔离 | `SPACK_USER_CONFIG_PATH=spack-workflow/user-config`、`SPACK_USER_CACHE_PATH=spack-workflow/user-cache` |
| builtin 真身 | `spack-workflow/user-cache/package_repos/fncqgg4/repos/spack_repo/builtin/packages/` |
| 用户 MPI 作业 | `pgrep -a mpirun` 无（阶段2 本就无安装动作，预检照做） |

---

## 步骤1：读取待安装清单

清单：`/home/zhangyuhang/workflow/stage2-packages/packages_to_install.yaml`（md5 `41738466a8132dc94937132cafde31cf`，本轮**未改动**）

实际待安装软件（非注释行）：

```
fds,6.9.1,both
su2,7.5.1,both
cmaq,5.3,both
swan,4145,both
roms,4.2,both
```

> 模板中 `#` 开头的 gromacs / lammps / openfoam / cp2k / quantum-espresso 均为格式示例，已跳过，不参与验证或安装。

### 步骤2~4：存在性 / 版本 / spec 解析（实测总表）

| 软件 | `spack location -p` | 指定版本在 Safe versions | `%gcc` spec | `%llvm`(clang@19.1.7) spec | 结论 |
|---|---|---|---|---|---|
| fds | ✅ builtin | ✅ 6.9.1 | ❌ RC=1 | ❌ RC=1 | **阻塞** |
| su2 | ✅ builtin | ✅ 7.5.1 | ✅ RC=0 | ✅ RC=0 | 可解析 |
| cmaq | ✅ builtin | ✅ 5.3 | ✅ RC=0（解析成 `@5.3.1`） | ✅ RC=0（`@5.3.1`） | 可解析 |
| swan | ✅ builtin | ✅ 4145 | ✅ RC=0 | ✅ RC=0 | 可解析 |
| roms | ✅ builtin | ✅ 4.2 | ✅ RC=0 | ✅ RC=0 | 可解析 |

探针实测：**`TOTAL pass=8 fail=2`**（2 个 FAIL 全部是 fds 的两条腿）。5 个包**全部来自 builtin**，无一来自 kp repo 或本地 repo。

`@X.Y` 是版本范围而非精确版：`cmaq@5.3` → 实际 concretize 为 `cmaq@5.3.1`（同前缀取最新）。本轮只有 cmaq 命中此坑（fds 6.9.1 / su2 7.5.1 / swan 4145 / roms 4.2 无同前缀新版本）。

### 步骤5：provider 路由证据（阶段3 可直接引用）

`spack spec` 文本里 grep 出的实际选中者：

| spec | 实际选中 | 说明 |
|---|---|---|
| `su2@7.5.1 %gcc` / `%llvm` | `kpblas@26.0.RC1` + `kplapack@26.0.RC1` | 默认 `~mkl~openblas~mpi` → **KML provider 确实生效**，非回落系统 blas |
| `swan@4145 %gcc` / `%llvm` | `hmpi@26.0.RC1` + `netcdf-c@4.10.0+mpi` + `hdf5@1.14.6+mpi` | 走鲲鹏 MPI |
| `roms@4.2 %gcc` / `%llvm` | `hmpi@26.0.RC1` + `netcdf-c@4.10.0+mpi` + `hdf5@1.14.6+mpi` | 同上（默认 `+mpi ~openmp roms_application=benchmark`） |
| `cmaq@5.3.1 %gcc` / `%llvm` | 仅 compiler-wrapper / gcc-runtime / glibc | builtin 配方 `build_system=generic`，**无 mpi/blas/netcdf 依赖** —— 纯手动构建脚手架，阶段3 需按源码自行补 netcdf/ioapi |

---

## ⚠ 阻塞项：fds@6.9.1（aarch64 不可解析）

`spack spec fds@6.9.1 %gcc` 完整报错：

```
==> Error: failed to concretize `fds@6.9.1 %gcc` for the following reasons:
     1. intel-oneapi-mkl: This package in only available for x86_64 and Linux
     2. intel-oneapi-mkl: This package in only available for x86_64 and Linux
        required because conflict is triggered when target=aarch64:
        required because conflict constraint
```

builtin `fds/package.py`（`$(spack location -p fds)/package.py`）原文位置：

- `:36` `depends_on("mkl")`
- `:40` `:48` `:52` `:58` `:64` 五处 `requires(...)`（含 `^intel-oneapi-mkl` policy=one_of、linux+%gcc 必 `^openmpi` 等）
- `:81` `mpi_mapping = {"openmpi": "ompi", "intel-oneapi-mpi": "impi"}`、`:82` `compiler_mapping = {"gcc": "gnu", "oneapi": "intel", "intel": "intel"}` → build target 由 mpi 名 + 编译器名拼出

→ 三重 x86/Intel 绑定（MKL + linux 必然 openmpi）；aarch64 上**无版本可解**（6.9.0 / 6.8.0 同配方同 `requires`，**降级无效**）。

**用户决策（2026-10-09 已确认）**：清单**不改**，fds 交由**阶段3 按 AI_INSTRUCTION 自写 package.py** —— 用 `kpblas`/`kplapack` 替 MKL、`hmpi` 替 openmpi，并重写 `build_targets` 的 mpi/compiler 映射。

---

## stage3 兼容性检查

- `install_batch.sh` 内置 `bisheng → %llvm` 映射，清单填 `both` / `bisheng` 均可正确展开。✅
- 清单 `compiler` 字段本轮全为 `both` → 每包按 gcc + llvm 各一条腿执行。
- 阶段3 决策树分流：**4 包走常规路径**（su2 / cmaq / swan / roms 可直接 `spack install`），**fds 走「自写 package.py」路径**（见上节）。

---

## 用户决策记录（2026-10-09，本轮）

| 项 | 决策 |
|---|---|
| 是否更新本文件 | ✅ 同意更新（本次即按同意写入） |
| fds 阻塞处理 | 清单不改，阶段3 自写 package.py（kpblas/kplapack 替 MKL、hmpi 替 openmpi） |
| cmaq 版本 | 清单保持 `5.3`（范围取最新，实际装 5.3.1），阶段3 按实际解析版本安装 |

---

## packages_to_install.yaml（保持原样，未改动）

```
fds,6.9.1,both
su2,7.5.1,both
cmaq,5.3,both
swan,4145,both
roms,4.2,both
```

---

## 完成标志

- ✅ `packages_to_install.yaml` 中有 5 个实际待安装软件（≥1）
- ✅ 5 个包名在 spack 中均验证存在（全部 builtin）
- ✅ su2 / cmaq / swan / roms 指定版本可用，`%gcc` + `%llvm` spec 全部解析通过（8 条腿 PASS）
- ⚠ fds@6.9.1 aarch64 阻塞（intel-one-api-mkl x86-only），已按用户决策记录处理路径：阶段3 自写 package.py
- ✅ 示例条目未被当作真实软件处理
- ✅ stage3 脚本 bisheng→llvm 映射确认，可进入阶段3
- ✅ 阶段2 未执行任何 `spack install`；`$ETC` site 配置与运行前备份逐字节一致（零漂移）
