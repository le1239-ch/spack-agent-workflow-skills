# 鲲鹏920F + Spack + BiSheng + KML：HPC 软件 Agent Workflow

## 概述

本工作流面向鲲鹏920F (aarch64) 平台，使用 Spack 包管理器 + BiSheng 编译器 + KML 鲲鹏数学库，
自动化安装 HPC 软件栈，并完成编译期优化和交付文档。

**设计原则：每步一个原子的、可验证的动作，AI Agent 可直接读取命令、执行、判断是否成功。**

> ⛔ **全局规则：禁止 AI Agent 自行修改任何 .md 文件。** 如需修改（记录结果、修正信息等），必须先向用户说明意图并获得同意。脚本自动生成的 .md 不受此限。详见 `docs/agent_orchestration.md`。

## 目录结构

```
workflow/
├── README.md                          # 本文件 — 总览
├── stage1-setup-spack/                # 阶段1：环境盘点 + Spack安装 + 鲲鹏repo配置 + HPCKit安装 + 编译器注册
│   ├── setup_spack.sh                 # 一体化脚本：探测+下载spack+克隆kp-spack+安装hpckit+注册编译器+验证
│   ├── AI_INSTRUCTION.md              # AI Agent 指令文档
│   ├── packages.yaml                  # packages.yaml 模板
│   ├── compilers.yaml                 # compilers.yaml 模板
│   ├── repos.yaml                     # repos.yaml 模板
│   └── DESCRIPTION.md                 # 步骤描述文件
│
├── stage2-packages/                   # 阶段2：待安装软件清单（手动填写）
│   ├── packages_to_install.yaml       # CSV格式清单（软件名,版本,编译器）
│   ├── AI_INSTRUCTION.md              # AI Agent 指令文档
│   └── DESCRIPTION.md                 # 步骤描述文件
│
├── stage3-install/                    # 阶段3：安装（含 package.py 编写 / 复制修改 / 失败移交）
│   ├── install_batch.sh               # 读取清单安装，含3次重试+handoff生成
│   ├── AI_INSTRUCTION.md              # AI Agent 指令（路径A/A2/B/C + stage3.5交互）
│   ├── install_log.md                 # 安装日志模板
│   ├── DESCRIPTION.md                 # 步骤描述文件
│   └── handoff_to_3.5.md              # 移交清单（转 stage3.5，运行时生成）
│
├── stage3.5-manual-build/             # 阶段3.5：手动编译兜底
│   ├── manual_build.sh                # 读取移交清单，手动编译，提取编译命令回传
│   ├── AI_INSTRUCTION.md              # AI Agent 指令文档
│   └── DESCRIPTION.md                 # 步骤描述文件
│
├── stage4-compile-opt/                # 阶段4：编译期优化
│   ├── compile_opt.sh                 # 编译优化重装脚本
│   ├── opt_packages.yaml              # 优化版 packages.yaml（含 flag 注入）
│   └── DESCRIPTION.md                 # 步骤描述文件
│
├── stage5-deliver/                    # 阶段5：交付
│   ├── deliver.sh                     # 为每个软件生成说明文档（安装命令+依赖树+描述）
│   ├── AI_INSTRUCTION.md              # AI Agent 指令文档
│   └── DESCRIPTION.md                 # 步骤描述文件
│
├── docs/
│   ├── agent_orchestration.md         # Agent 编排指南（任务拆分 + 契约）
│   ├── failure_handling.md            # 失败处理策略
│   └── spack_package_guide.md         # Spack package.py 编写精简指南
│
├── scripts/
│   ├── lib_common.sh                  # 公共函数库（日志、校验、环境加载）
│   └── run_all.sh                     # 全流程串联脚本
│
└── templates/                          # 各阶段产出模板
    ├── env_report.md
    └── install_log.md
```

## 流程总览

```
Stage 1                    Stage 2              Stage 3                    Stage 3.5             Stage 4          Stage 5
环境盘点+Spack安装    →    待装清单(手动填写) →  安装                    →  手动编译兜底      →    编译优化    →    交付
+鲲鹏repo配置               packages_to_install   包存在→直接装                 手动编译安装           (--fresh重编)    (每软件输出md)
+HPCKit安装                                       安装失败→复制+改package.py   成功→回传编译命令
+编译器注册                                       3次重试失败→转3.5            给stage3写package.py
                                                  包不存在→写package.py        2次写不出→失败跳过
                                                  3次重试失败→转3.5            3次编译失败→失败跳过
  │                        │                    │                          │                    │                │
  ▼                        ▼                    ▼                          ▼                    ▼                ▼
setup_spack.sh         packages_to_install  install_batch.sh           manual_build.sh     compile_opt.sh  deliver.sh
  │                        │                    │                          │                    │                │
  ▼                        ▼                    ▼                          ▼                    ▼                ▼
env_report.md          (用户填写)            install_log.md             manual_build_log.md  opt_pkgs.yaml    <软件名>.md
+packages.yaml                               (包名/编译器/              handoff_to_3.md       (flag注入)       (安装命令+依赖树+
+compilers.yaml                               hash/状态/重试)            (回传编译命令)                          描述)
+repos.yaml                                  handoff_to_3.5.md
                                             (移交手动编译)
```

## 各阶段通过条件

| 阶段 | 通过条件 | 交付物 |
|------|----------|--------|
| 1 | spack 可用、kp-spack repo 挂载、hpckit 安装、编译器注册、spec 解析 | `env_report.md` / `packages.yaml` / `compilers.yaml` / `repos.yaml` |
| 2 | `packages_to_install.yaml` 中至少有 1 个软件 | `packages_to_install.yaml` |
| 3 | 每个包 `spack find -l` 能查到（或 ❌ 失败已跳过） | `install_log.md` / `handoff_to_3.5.md`（可选） |
| 3.5 | 手动编译成功的包回传编译命令；失败的包记录跳过 | `manual_build_log.md` / `handoff_to_3.md` |
| 4 | 性能关键包用 KML 重编成功 | `opt_packages.yaml` |
| 5 | 每个已安装软件都有 `.md` 文档 | `<软件名>.md` |

## 快速开始

```bash
# 1. 环境盘点 + 自动安装 spack + 配置鲲鹏 repo + 安装 hpckit + 注册编译器
cd stage1-setup-spack && bash setup_spack.sh

# 2. 手动填写软件清单
cd ../stage2-packages && vi packages_to_install.yaml

# 3. 安装（路径A直接装/A2复制改/B新写package.py，3次重试 → 失败转3.5）
#    正式流程由 Agent 按 stage3-install/AI_INSTRUCTION.md 的决策树逐个执行；
#    下面这条是批处理模式（无人交互/复现）入口：
source /home/zhangyuhang/workflow/scripts/spack-env.sh   # 统一环境入口（含 user scope 隔离）
cd ../stage3-install && bash install_batch.sh

# 3.5. 手动编译兜底（如有移交清单）
cd ../stage3.5-manual-build && bash manual_build.sh

# 3C. 据手动编译命令写 package.py（如有回传清单）
cd ../stage3-install && bash install_batch.sh --from-3.5

# 4. 编译优化
cd ../stage4-compile-opt && bash compile_opt.sh

# 5. 交付 — 生成软件说明文档
cd ../stage5-deliver && bash deliver.sh
```

或一键串联（**batch 模式：会用批处理脚本替代阶段3/3.5 的 Agent 决策**）：
```bash
bash scripts/run_all.sh                     # 完整流程
bash scripts/run_all.sh --skip-install      # 只做阶段1/2/5（跳过 3 / 3.5 / 4）
bash scripts/run_all.sh --skip-optimize     # 只跳过阶段4
```

## 环境入口与 scope 隔离

```bash
# 手动执行任何 spack 命令前先 source 这个：独立 spack + user scope 隔离到工作流目录
source /home/zhangyuhang/workflow/scripts/spack-env.sh
```

- user scope：`spack-workflow/user-config/`，缓存：`spack-workflow/user-cache/`
- **为什么隔离**：`/root/.spack` 是 root 全局 user scope，里面还注册着其他项目的 repo
  （实测会让本工作流解析到 **191 个外来 `*-opt` 包**，并与 kp repo 同名 namespace 冲突）；
  且 spack 1.x 的编译器 externals 只存在于 user scope，不隔离就无法随工作流搬迁。
- **首次迁移**（自动，见 `scripts/lib_common.sh` 的 `init_workflow_user_scope`）：
  把 `/root/.spack/packages.yaml`（编译器 externals）与本工作流的本地 repo 注册迁入
  工作流 user scope，其他项目 repo 一律不带过来。

## 依赖的 Skill

本工作流基于以下 Hermes Skill 构建：
- `kunpeng920-migration-workflow` — 鲲鹏920端到端迁移流程框架
- `kunpeng920-env-hpckit` — HPCKit 环境与组件路径
- `spack-new-package` — HPCKit 生态 Spack 打包规范
  - **工作流内全量副本（stage3 / stage4 直接使用）**：`docs/spack-new-package/SKILL.md` + `docs/spack-new-package/references/`（10 个 reference，逐字节同步自 `~/.hermes/skills/kerminal/spack-new-package/`）
  - 精简速查版：`docs/spack_package_guide.md`（保留作快速查阅）

## 鲲鹏数学库及优化组件（kp-spack 仓库）

从 kp-spack 仓库（`kunpeng920prof` 分支）拉取的 14 个鲲鹏优化包，替换开源等价物以获得鲲鹏920平台性能提升：

| 类别 | 包名 | 替换的开源等价物 | 功能 |
|------|------|-----------------|------|
| MPI | `hmpi` | OpenMPI | 鲲鹏优化MPI通信库 |
| 套件 | `hpckit` | — | HPC开发套件元包（含编译器+MPI+数学库） |
| BLAS | `kpblas` | OpenBLAS | 基础线性代数（矩阵乘/向量运算） |
| | `kpspblas` | — | 稀疏矩阵BLAS |
| LAPACK | `kplapack` | LAPACK | 高级线性代数求解（特征值/SVD） |
| | `kpscalapack` | ScaLAPACK | 分布式并行LAPACK |
| | `kpscasolver` | — | 分布式求解器 |
| | `kpsolver` | — | 直接求解器 |
| FFT | `kpfft` | FFTW | 快速傅里叶变换 |
| | `kpfftw` | FFTW | FFTW接口兼容层 |
| 向量 | `kpvml` | — | 向量数学函数库 |
| | `kpksvml` | — | 短向量数学函数库 |
| 其他 | `kpkupl` | — | 鲲鹏通用性能库 |
| | `kpkml` | — | KML元包（聚合上述子库的统一入口；**无 `provides()`**，不能作 BLAS/LAPACK 的 provider 约束） |

> provider 指向要写**真实 `provides()` 的包**：`packages.yaml` 中 `all.providers` 用 `blas: [kpblas]` / `lapack: [kplapack]` / `mpi: [hmpi]`，所有 HPC 软件才会自动链接到鲲鹏优化数学库。
> ⚠ 写 `blas: [kpkml]` 或用 `require: kpkml` **无效**（`kpkml` 是元包、无 `provides()`）——前者会被默认的 `openblas` 掩盖，后者会让所有 concretization 报 `cannot satisfy a requirement for package 'blas'`。
