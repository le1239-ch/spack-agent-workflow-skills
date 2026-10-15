# Agent 编排指南

## 概述

本工作流拆分为独立的 task，每个 task 对应一个阶段。Task 之间通过文件传递输入/输出，不共享状态。

## 任务拆分

```
task_01_setup_spack     → 环境盘点 + 下载spack + 克隆kp-spack repo + 安装hpckit + 注册编译器 + 验证spec
task_02_packages        → 用户手动填写 packages_to_install.yaml
task_03_install         → 按清单安装（路径A直接装/A2复制改/B新写package.py，3次重试→转3.5）
task_03.5_manual_build  → 手动编译兜底（3次重试，成功→回传编译命令给stage3路径C）
task_04_compile_opt     → 性能关键包 --fresh 重编
task_05_deliver         → 为每个软件生成说明文档（安装命令+依赖树+描述）
```

## 依赖关系

```
task_01_setup_spack
    │
    ▼
task_02_packages (用户手动填写)
    │
    ▼
task_03_install (路径A/A2/B，3次重试) ──失败──→ task_03.5_manual_build (手动编译3次重试)
    │                                              │
    │                                              ├── 成功 → 回传编译命令 → task_03 路径C (2次重试)
    │                                              │            ├── 成功 → ✅
    │                                              │            └── 失败 → ❌ 跳过
    │                                              └── 失败 → ❌ 跳过
    │
    ▼
task_04_compile_opt
    │
    ▼
task_05_deliver
```

### 串行部分（必须按顺序）

```
task_01 → task_02 → task_03 → [task_03.5 → task_03路径C] → task_04 → task_05
```

## 每个 task 的 Agent 契约

### 通用契约

| 项目 | 说明 |
|------|------|
| 输入 | 明确的包名列表 / 文件路径 |
| 允许动作 | `spack spec`、`spack install`、`spack find`、编辑 `packages.yaml` |
| 禁止动作 | 改官方 recipe（自定义放自己的 repo） |
| 输出 | 结构化 log（包名 / 状态 / hash / 错误摘要） |
| 失败策略 | 最多重试 1 次（变体或约束），仍失败则记录并跳过 |

### ⛔ 全局禁止规则：不得自行修改 .md 文件

**任何阶段的 AI Agent 都不得自行修改、覆写、追加任何 `.md` 文件。** 包括但不限于：

- `env_report.md`、`install_log.md`、`package_verification.md`
- `DESCRIPTION.md`、`AI_INSTRUCTION.md`
- 交付文档 `<软件名>.md`

如果 Agent 执行过程中有修改 .md 文件的需求（例如记录验证结果、补充说明、修正错误信息），**必须先向用户说明意图并获得明确同意后才能写入**。

> 脚本（`setup_spack.sh`、`install_batch.sh`、`deliver.sh` 等）自动生成的 .md 输出不受此限制——此规则仅约束 AI Agent 的直接编辑行为。

### 各 task 详细契约

#### task_01_setup_spack

| 项目 | 值 |
|------|-----|
| 脚本 | `stage1-setup-spack/setup_spack.sh` |
| AI 指令 | `stage1-setup-spack/AI_INSTRUCTION.md` |
| 输入 | 无 |
| 输出 | `env_report.md` + `packages.yaml` / `compilers.yaml` / `repos.yaml` |
| 允许动作 | 只读探测 + `curl` 下载 spack + `git clone` kp-spack + `spack install hpckit` + `spack compiler find` + 写配置文件 |
| 禁止动作 | 安装 HPC 应用包（阶段3才装）、改官方 recipe |
| 超时 | 30 分钟 |
| 通过条件 | spack 可用、kp-spack repo 挂载、hpckit 安装、编译器注册、spec 解析成功 |

#### task_02_packages

| 项目 | 值 |
|------|-----|
| 脚本 | 无（用户手动填写） |
| AI 指令 | `stage2-packages/AI_INSTRUCTION.md` |
| 输入 | 阶段1 配置完成 |
| 输出 | `packages_to_install.yaml` |
| 通过条件 | 至少有 1 个软件 |

#### task_03_install

| 项目 | 值 |
|------|-----|
| 脚本 | `stage3-install/install_batch.sh` |
| AI 指令 | `stage3-install/AI_INSTRUCTION.md` |
| 输入 | `packages_to_install.yaml` + `handoff_to_3.md`（可选，来自 stage3.5） |
| 输出 | `install_log.md` + `handoff_to_3.5.md`（可选） + package.py |
| 允许动作 | `spack spec`/`install`/`find`/`info`、复制官方 package.py 到本地 repo、编写 package.py、`source setvars.sh`（仅 stage3.5） |
| 禁止动作 | 改官方 repo 中的原始 recipe、改 kp*/hmpi 包、写 package.py 时 source setvars.sh |
| 失败策略 | 路径A2/B 各3次重试 → 转 stage3.5 → 路径C 2次重试 → 失败跳过 |
| 超时 | 每包每编译器版本 30 分钟 |

#### task_03.5_manual_build

| 项目 | 值 |
|------|-----|
| 脚本 | `stage3.5-manual-build/manual_build.sh` |
| AI 指令 | `stage3.5-manual-build/AI_INSTRUCTION.md` |
| 输入 | `stage3-install/handoff_to_3.5.md` |
| 输出 | `manual_build_log.md` + `handoff_to_3.md` + `build.sh` |
| 允许动作 | `source setvars.sh`、下载源码、`./configure`/`cmake`/`make`、写构建脚本、写 handoff 文件 |
| 禁止动作 | 改官方 spack recipe、改 kp*/hmpi 包、`spack install`（本阶段不用 spack 安装） |
| 失败策略 | 每包最多 3 次重试，仍失败则记录跳过 |
| 超时 | 每包 1 小时 |

#### task_04_compile_opt

| 项目 | 值 |
|------|-----|
| 脚本 | `stage4-compile-opt/compile_opt.sh` |
| 输入 | `install_log.md` |
| 输出 | `compile_opt_log.md` / `opt_packages.yaml` |
| 允许动作 | `spack config add`、`spack install --fresh`、`spack find -l` |
| 失败策略 | 1次重试，仍失败则记录跳过 |
| 超时 | 每包 1 小时 |

#### task_05_deliver

| 项目 | 值 |
|------|-----|
| 脚本 | `stage5-deliver/deliver.sh` |
| AI 指令 | `stage5-deliver/AI_INSTRUCTION.md` |
| 输入 | `install_log.md` |
| 输出 | `<软件名>.md`（每软件一份：安装命令+依赖树+描述） |
| 允许动作 | `spack find`、`spack deps`、`spack info`、`spack location -i`、写文件 |
| 禁止动作 | 安装/卸载包、改配置 |
| 超时 | 10 分钟 |

## 失败处理策略

### 3 类允许的修复动作

1. **换 variant** — 去掉部分 variant
2. **加 `^` 约束** — 明确依赖版本
3. **修改/新写 package.py** — 复制官方到本地 repo 修改，或从源码新写

### 重试规则（Stage3 + Stage3.5）

| 路径 | 场景 | 修改重试次数 | 全部失败后 |
|------|------|------------|----------|
| A2 | 已有包安装失败→复制+修改官方 package.py | 3 次 | 转 stage3.5 |
| B | 包不存在→新写 package.py | 3 次 | 转 stage3.5 |
| 3.5 | 手动编译 | 3 次 | ❌ 失败跳过 |
| C | 据手动编译命令写 package.py | 2 次 | ❌ 失败跳过 |

### 不允许的动作

- 修改官方 spack recipe（`builtin/packages/` 下的原始 `package.py`）
- 修改 kp* / hmpi 等基础设施数学库包
- 并行安装同一包的两个编译器版本
- 重新编译底层框架

## 鲲鹏数学库及优化组件（kp-spack 仓库 14 个包）

从 kp-spack 仓库拉取的鲲鹏优化包，禁止修改其 package.py：

| 类别 | 包名 | 替换的开源等价物 | 功能 |
|------|------|-----------------|------|
| MPI | `hmpi` | OpenMPI | 鲲鹏优化MPI通信库 |
| 套件 | `hpckit` | — | HPC开发套件元包（编译器+MPI+数学库） |
| BLAS | `kpblas` | OpenBLAS | 基础线性代数 |
| | `kpspblas` | — | 稀疏矩阵BLAS |
| LAPACK | `kplapack` | LAPACK | 高级线性代数求解 |
| | `kpscalapack` | ScaLAPACK | 分布式并行LAPACK |
| | `kpscasolver` | — | 分布式求解器 |
| | `kpsolver` | — | 直接求解器 |
| FFT | `kpfft` | FFTW | 快速傅里叶变换 |
| | `kpfftw` | FFTW | FFTW接口兼容层 |
| 向量 | `kpvml` | — | 向量数学函数库 |
| | `kpksvml` | — | 短向量数学函数库 |
| 其他 | `kpkupl` | — | 鲲鹏通用性能库 |
| | `kpkml` | — | KML元包（聚合上述子库的统一入口） |

## 文件流转图

```
env_report.md ←── setup_spack.sh (探测+安装spack+克隆kp-spack+配置+安装hpckit+注册编译器+验证spec)
packages.yaml      │
compilers.yaml     │
repos.yaml         │
                   ▼
packages_to_install.yaml (用户手动填写)
                   │
                   ▼
install_log.md ←── install_batch.sh (按清单 gcc+bisheng / 三路径) ──── compile_opt_log.md
                                                                     │
                                                                     ▼
                                                           <软件名>.md ←── deliver.sh
                                                           (安装命令+依赖树+描述)
```
