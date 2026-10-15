# 阶段 4：编译期优化 — 描述文件

## 目标

对性能关键包用 KML 数学库重编，注入 BiSheng 鲲鹏920 优化 flag。**只改 flags，不改配方。**

## 输入

- `install_log.md`（来自阶段3）— 确认已安装的包
- `packages.yaml`（来自阶段1）— 基础配置

## 动作清单

### 步骤 4.1 确认 BiSheng 鲲鹏推荐 flag
```bash
# BiSheng 官方推荐鲲鹏920:
-mcpu=tsv110 -march=armv8.2-a -O3

# ⚠ -flto 会禁用 SVE 自动向量化 → 不要加
# ⚠ -ffast-math 对含 LAPACK 的科学软件不安全 → 仅限安全场景
# ✅ GCC 默认 FP 语义最优（不设 -ffast-math 也不设 -ffp-contract=off）
```

### 步骤 4.2 在 packages.yaml 做全局注入
```yaml
packages:
  all:
    compiler: [bisheng]
    target: [aarch64]
  fftw:
    variants: [+openmp, +shared]
  openmpi:
    variants: [+pmi, +cxx, +fortran]
  gromacs:
    variants: [+mpi, ~cuda, build_type=Release]
```

### 步骤 4.3 用 KML 重编性能关键包
```bash
spack install --fresh petsc ^kpblas ^kplapack
spack install --fresh gromacs ^kpblas ^kplapack
```

**鲲鹏数学库及优化组件（14个包）重编说明**：

KML 注入用 **provider 约束** `^kpblas ^kplapack`，**不要用 `^kpkml`**（kpkml 是元包、无 `provides()`，实测直连报 `'kpkml' is not a possible dependency of any root spec`）。下表中 `kpblas`/`kplapack` 可直接作约束，其余子组件（`kpfftw`/`kpscalapack` 等）stage4 未实测采用：

| 类别 | 包名 | 替换的开源等价物 | 适用优化场景 |
|------|------|-----------------|-------------|
| MPI | `hmpi` | OpenMPI | MPI通信密集型应用（通过 provider 全局指向） |
| BLAS | `kpblas` | OpenBLAS | 矩阵乘/向量运算密集型 |
| | `kpspblas` | — | 稀疏矩阵运算 |
| LAPACK | `kplapack` | LAPACK | 特征值/SVD 求解 |
| | `kpscalapack` | ScaLAPACK | 分布式并行线性代数 |
| | `kpscasolver` | — | 分布式求解器 |
| | `kpsolver` | — | 直接求解器 |
| FFT | `kpfft` | FFTW | 频谱分析/信号处理 |
| | `kpfftw` | FFTW | FFTW接口兼容 |
| 向量 | `kpvml` | — | 向量数学函数 |
| | `kpksvml` | — | 短向量数学函数 |
| 其他 | `kpkupl` | — | 通用性能加速 |

**注意：** 只对性能关键包（BLAS/LAPACK/FFT/PETSc/应用本身）重编，不要全部 `--fresh`。

## 性能关键包列表

| 包名 | 原因 | 优化 flag |
|------|------|-----------|
| fftw | FFT 核心库 | -O3 -mcpu=tsv110 +openmp |
| scalapack | 并行 BLAS | -O3 -mcpu=tsv110 ^kpblas ^kplapack |
| petsc | 线性求解器 | -O3 -mcpu=tsv110 ^kpblas ^kplapack |
| gromacs | MD 应用 | -O3 -mcpu=tsv110 ~cuda |
| lammps | MD 应用 | -O3 -mcpu=tsv110 |
| openfoam | CFD 应用 | -O3 -mcpu=tsv110 |
| quantum-espresso | 量子化学 | -O3 -mcpu=tsv110 ^kpblas ^kplapack |
| cp2k | 量子化学 | -O3 -mcpu=tsv110 ^kpblas ^kplapack |

## 脚本

`compile_opt.sh` — 自动执行上述全部步骤：

```bash
# 优化默认性能关键包列表
bash compile_opt.sh

# 或指定特定包
bash compile_opt.sh petsc gromacs
```

## 鲲鹏920 SVE 优化注意事项

基于 `spack-new-package` skill 实测经验（工作流内全量副本：`docs/spack-new-package/SKILL.md` + `references/kalign-sve-optimization.md`）：

| 问题 | 后果 | 规避 |
|------|------|------|
| spack compiler-wrapper 静默禁用 SVE | wrapper 传了 `-mcpu=native`，编译产物却 **0 条** SVE 指令 | **绕过 wrapper**：在 `setup_build_environment` 里把 `CC`/`CXX` 设为 HPCKit gcc 绝对路径（实测修复后二进制 SVE 指令 100+）；接受默认行为＝白丢 SVE |
| -flto 禁用 GCC SVE 向量化 | SVE 指令消失 | 不要加 -flto |
| -ffast-math 破坏浮点收敛循环 | 程序挂起/崩溃 | GCC 默认 FP 语义最优，不设 -ffast-math |
| libgomp vs libomp | OpenMP task 密集型 60%+ 开销 | task 密集型优先 GCC（libgomp） |

## 输出

| 文件 | 说明 |
|------|------|
| `compile_opt_log.md` | 重编日志：包名/原hash/新hash/状态/KML/flag |
| `opt_packages.yaml` | 优化版 packages.yaml（含 flag 注入） |

## Agent 契约

| 项目 | 值 |
|------|-----|
| 允许动作 | `spack config add`、`spack install --fresh`、`spack find -l` |
| 禁止动作 | 全部 `--fresh` 重来、改官方 recipe |
| 输入 | `install_log.md` |
| 输出 | `compile_opt_log.md` / `opt_packages.yaml` |
| 失败策略 | 1次重试（去掉 ^kpblas ^kplapack 约束），仍失败则记录跳过 |
| 超时 | 每包 1 小时 |
