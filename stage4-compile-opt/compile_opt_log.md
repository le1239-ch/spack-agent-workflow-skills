# 编译期优化日志 (compile_opt_log.md)

> 阶段4 执行记录（2026-09-28，由执行 Agent 维护）。
> 范围依据 AI_INSTRUCTION「只对性能关键包重编，install_log.md 中没有的包跳过」：stage3 install_log.md 中成功的性能关键包仅 **gromacs**（4 腿）；fftw/scalapack/petsc/lammps/openfoam/quantum-espresso/cp2k 未在 stage3 安装 → 全部跳过，未做任何全新编译。
> 执行方式说明：脚本 4.2/4.3 实测存在缺陷（见下方「脚本缺陷与等价执行」），本阶段按「只改 flags、不改配方」原则用实测验证过的等价命令执行，未触碰任何 recipe。

## 重编结果

| 包名 | 编译器 | 原hash | 新hash | 状态 | KML | 优化flag | 备注 |
|------|--------|--------|--------|------|-----|----------|------|
| gromacs@2025.3 | %gcc@12.3.1 | 7qlegwa | **6mlfzvp** | ✅ 成功 | kpblas@26.1.RC1 + kplapack@26.1.RC1 | `-O3 -mcpu=tsv110`（C/CXX） | BLAS+LAPACK 双 KML 直链（修复后重编，见注2）；libkblas+libklapack NEEDED ×3 |
| gromacs@2025.3 | %llvm(bisheng@19.1.7) | mlztgo7 | — | ❌ 跳过 | — | — | spack 求解器缺陷（见注3），按失败契约回落重试后仍失败 |
| gromacs@2024.6 | %gcc@12.3.1 | wefpq24 | **zuxzmoa** | ✅ 成功 | kpblas@26.1.RC1 + kplapack@26.1.RC1 | `-O3 -mcpu=tsv110`（C/CXX） | 同上修复后重编；libkblas+libklapack NEEDED ×3 |
| gromacs@2024.6 | %llvm | efycmlv | — | ⏭ 跳过 | — | — | 同 %llvm 腿求解器缺陷，不重复消耗 |

## KML 注入实证（gromacs@2025.3 %gcc 腿）

| 证据项 | 实测结果 |
|--------|----------|
| `spack find -d /i3k2e4s` | 依赖树含 kpblas@26.1.RC1、kplapack@26.1.RC1，openblas 已不在树中 |
| 构建环境 `.spack/spack-build-env.txt` | `SPACK_CFLAGS='-O3 -mcpu=tsv110'`、`SPACK_CXXFLAGS='-O3 -mcpu=tsv110'` |
| 构建日志 tsv110 出现次数 | 996 处（编译命令实际携带 flag） |
| `readelf -d lib64/libgromacs_mpi.so.10` | NEEDED 含 `libklapack.so.1` → `kml/gcc/lib/sve512/`（KML ISA 目录，直链成功） |
| 构建日志 cmake 参数 | `-DGMX_LAPACK_USER=<...>/kml/gcc/lib/sve512/libklapack.so` |
| `gmx_mpi --version`（spack load 后） | GROMACS version: 2025.3-spack；MPI: Open MPI v4.1.6rc4(hmpi)；CPU FFT: fftw-3.3.10-neon |

2024.6 腿（dqhcrnt）实测同上形态：依赖树含 kpblas/kplapack、`readelf -d` 三个主库 NEEDED 均含 `libklapack.so.1`、构建日志 tsv110 出现 972 处、`gmx_mpi --version` = 2024.6-spack 正常。

## 注1：脚本缺陷与等价执行（compile_opt.sh）

| 缺陷 | 实测证据 | 等价执行方式 |
|------|----------|--------------|
| 4.2 写入 `packages:blas/lapack: require: kpkml` | kpkml 是元包、无 `provides()`，毒行导致所有 concretization 报 `cannot satisfy a requirement for package 'blas'` | 已清除毒行（site/packages.yaml 现值无 require: kpkml），改用命令行 `^kpblas ^kplapack`（两者真实 provides blas/lapack） |
| 4.3 `^kpkml` 直连 | `spack spec gromacs ^kpkml` → `'kpkml' is not a possible dependency of any root spec` | provider 形式约束（kpblas/kplapack，覆盖 BLAS/LAPACK 场景；kpfftw 未采用，见注4） |
| 默认列表含 7 个未安装包 | 直接跑默认列表会对 petsc/lammps 等未装包触发全新编译，违反「只对性能关键包重编」 | 仅对 install_log 中实际存在的 gromacs 执行 |
| `--fresh` | 会无谓重建 fftw/openblas/cmake 等已装依赖 | 用 `--fresh-roots`（根+新依赖重建，其余复用），符合「不要全部 --fresh」契约 |
| `spack config --scope=site add` 落点 | 写入的是 `$ETC/site/packages.yaml` 而非 `$ETC/packages.yaml` | 漂移检查两处均已覆盖；site 中保留脚本设计内的 variants 注入（fftw/openmpi/gromacs） |

## 注2：kpblas wrapper ISA 映射 bug（已经用户授权修复并重编验证）

- 本机 CPU：`CPU implementer 0x48` / `CPU part 0xd22`（鲲鹏920 TaiShan v110）。
- 原始 bug：`kpblas/package.py` `_ISA_MAP` 将 `0x48-0xd22` 映射到 `sme`，但 KML 26.1.RC1 无 `kml/gcc/lib/sme/` 目录 → `kpblas.libs` 解析为空 → `GMX_BLAS_USER` 未设置 → BLAS 回落系统 `/usr/lib64/libopenblas.so.0`。
- **修复时的重要修正**：最初拟改为 `sve512`（kplapack 用值），实测发现 `lib/sve512/` 下只有 libklapack/kspblas/kfft，**无 libkblas**；libkblas 实际位于 `matrix|sve|neon` 各自的 `kblas/{multi,locking,nolocking}/`。故最终改为 **`"0x48-0xd22": "sve"`**，与默认 `kblas_mode=multi` 拼出 `lib/sve/kblas/multi/libkblas.so`（实际存在）。
- 修复生效方式：package.py 改动不改 DAG hash，已 `spack uninstall` 旧 kpblas/两腿 gromacs 后重装（kpblas 新 hash ffmxwpd）。
- **重编后实证（两腿均过）**：gromacs@2025.3=`6mlfzvp`、2024.6=`zuxzmoa`；依赖树含 kpblas/kplapack；`readelf -d` NEEDED 同时含 `libkblas.so.1 ×3 + libklapack.so.1 ×3`（系统 openblas 消失）；build-out `-DGMX_BLAS_USER=…/sve/kblas/multi/libkblas.so` 与 `-DGMX_LAPACK_USER=…/sve512/libklapack.so`；`gmx_mpi --version` 两版本均正常。

## 注3：%llvm(bisheng) 腿求解器缺陷证据链

| 尝试 | 形态 | 结果 |
|------|------|------|
| 1 | `%llvm + flags + ^kpblas ^kplapack ^kpfftw` | concretize 挂起 ≥540s（多次）或报 `Only external, or concrete, compilers are allowed for the fortran language` + `cp2k: conflicts with '%clang'` 死锁 |
| 2 | `%llvm + flags + ^kpblas ^kplapack`（同 gcc 成功形态） | 快速失败，同一死锁错误（INSTALL_RC=1） |
| 3 | `%llvm + flags`（回落：去 KML 约束，契约第 1 次重试） | spack ASP 求解器内部错误（`Please report a bug`，INSTALL_RC=1） |
| 4 | 同上重试（契约第 2 次即封顶） | 再次 ASP 内部错误（INSTALL_RC=1） |
| 对照 | `%llvm + ^kpblas ^kplapack`（**无 flags**） | concretization 成功 → 失败触发因子锁定为 `%llvm × flags × kp` 组合 |

## 注4：FFT 覆盖说明

kpfftw provides `fftw-api@3`（KML FFTW 兼容层），尝试纳入约束后与 %llvm/flags 组合必触发死锁，且 %gcc 形态含 kpfftw 时求解时间剧增。本次 %gcc 腿保留官方 fftw@3.3.10（neon 优化）作 FFT provider，KML 覆盖 LAPACK 场景；kpfftw 的引入留待后续单独验证。

## 环境与配置合规

| 项目 | 状态 |
|------|------|
| site 配置漂移 | `$ETC/{config,repos,packages}.yaml` 零漂移；`$ETC/site/packages.yaml` 仅保留脚本设计内 variants（毒行已清除） |
| 备份 | `.config-backup-20260928-160723/`（三件套） |
| 指令文件 | AI_INSTRUCTION.md / DESCRIPTION.md 执行前后 sha256 一致（见执行报告） |
| 磁盘 | 重编 gromacs 单腿新增 ~1GB 内 |
| 超时 | 单腿构建 ~8 分钟（608 核），远低于 1 小时上限 |
