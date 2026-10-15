# 阶段 3：安装软件 — 描述文件

## 目标

读取 `packages_to_install.yaml`，对每个软件用指定编译器（gcc/bisheng）安装。
**包可能不存在于 spack——Agent 需编写 package.py。**
**安装失败时最多修改重试 3 次，仍失败则转交 stage3.5 手动编译兜底。**

## 输入

- `packages_to_install.yaml`（来自阶段2）— CSV 格式清单
- `stage3.5-manual-build/handoff_to_3.md`（来自 stage3.5，可选）— 手动编译成功的编译命令

## 完整安装流程（决策树）

```
软件在 spack 中存在？（spack info <name>）
│
├── 是 → 路径A：直接安装已有包
│   ├── spack install <name>@<version> %<compiler>
│   │   ├── 成功 → ✅ → stage4
│   │   └── 失败 → 路径A2：复制+修改已有 package.py
│   │       ├── 复制官方 package.py + 补丁文件到本地 repo
│   │       ├── 修改 → spack install（重试1/2/3，共3次修改机会）
│   │       │   ├── 任一成功 → ✅ → stage4
│   │       │   └── 3次均败 → 转 stage3.5
│   │       └── 不得修改官方 repo 中的原始文件，只改本地副本
│
├── 否 → 路径B：分析源码编写新 package.py
│   ├── git clone 源码，分析构建系统
│   ├── 参考 docs/spack-new-package/SKILL.md（全量知识库）+ docs/spack_package_guide.md（速查）编写 package.py
│   ├── depends_on 声明 hmpi/kpkml 依赖
│   ├── spack install（重试1/2/3，共3次修改机会）
│   │   ├── 任一成功 → ✅ → stage4
│   │   └── 3次均败 → 转 stage3.5
│   └── 共3次修改重试机会
│
└── stage3.5 回传 → 路径C：据编译命令写 package.py
    ├── 读取 handoff_to_3.md（手动编译成功的编译命令）
    ├── 编写 package.py → spack install（重试1/2，共2次修改机会）
    │   ├── 任一成功 → ✅（package.py from manual）→ stage4
    │   └── 2次均败 → ❌ 失败，跳过该软件 → stage4
    └── 手动编译成功但 package.py 写不出 = 整体失败
```

## 重试规则汇总

| 路径 | 场景 | 首次安装 | 修改重试 | 全部失败后 |
|------|------|---------|---------|----------|
| A | 已有包直接装 | 1次 | — | 转 A2 |
| A2 | 复制+修改已有 package.py | 1次 | 3次 | 转 stage3.5 |
| B | 新写 package.py | 1次 | 3次 | 转 stage3.5 |
| — | stage3.5 手动编译 | 1次 | 3次 | ❌ 失败跳过 |
| C | 据手动编译命令写 package.py | 1次 | 2次 | ❌ 失败跳过 |

## 三种安装路径详解

| 情况 | 处理方式 | HPCKit 依赖方式 | 重试次数 |
|------|----------|----------------|---------|
| 包在 spack builtin 或 kunpeng920prof repo 中 | 直接 `spack install` | 无需额外处理 | 失败→转A2 |
| 包存在但安装失败（A2） | 复制 package.py+patch 到本地 repo，修改后重装 | package.py 中用 `depends_on` | 3次 |
| 包不存在（B） | 分析源码+GitHub文档，编写 package.py | package.py 中用 `depends_on` | 3次 |
| stage3.5 回传（C） | 据手动编译命令编写 package.py | package.py 中用 `depends_on` | 2次 |

**关键规则**：package.py 方式用 `depends_on` 注入依赖（不 source setvars.sh）；手动编译（stage3.5）才 source setvars.sh。两种方式不混用。

> **本地 repo**：stage3 的 `install_batch.sh` 开头自动调用 `create_local_repo()` 创建（基于 CPU 型号命名，含 `spack_repo/<namespace>/` 路径结构），自写 package.py 和复制的官方 package.py 均存放于此。本地 repo 优先级高于 builtin，修改后的 package.py 会覆盖官方版本。

## 与 stage3.5 的交互

### stage3 → stage3.5（移交）

当路径A2或路径B的3次重试均失败时：

1. 写入 `handoff_to_3.5.md`（移交清单：包名/编译器/版本/spec/失败原因/源码URL/本地package.py路径）
2. 执行 `bash stage3.5-manual-build/manual_build.sh`
3. AI Agent 参照 `stage3.5-manual-build/AI_INSTRUCTION.md` 执行手动编译

### stage3.5 → stage3（回传）

当 stage3.5 手动编译成功时：

1. stage3.5 提取编译命令，写入 `handoff_to_3.md`
2. stage3 读取 `handoff_to_3.md`，路径C：据编译命令编写 package.py
3. spack install（最多2次修改重试）
4. 成功 → ✅；2次均败 → ❌ 失败跳过

## 鲲鹏数学库及优化组件 depends_on 参考（14个包）

在 package.py 中声明鲲鹏库依赖时，`kpkml` 是元包，直接 `depends_on("kpkml ...")` 即可拉入全部 KML 子组件：

| 类别 | 包名 | 功能 | depends_on 声明方式 |
|------|------|------|---------------------|
| MPI | `hmpi` | 鲲鹏优化MPI | `depends_on("hmpi compiler_variant=gcc", when="%gcc")` 单独声明 |
| 套件 | `hpckit` | HPC开发套件元包 | `depends_on("hpckit", type="build")` 单独声明 |
| BLAS | `kpblas` / `kpspblas` | 基础/稀疏BLAS | 通过 `kpkml` 元包拉入 |
| LAPACK | `kplapack` / `kpscalapack` / `kpscasolver` / `kpsolver` | LAPACK系列 | 通过 `kpkml` 元包拉入 |
| FFT | `kpfft` / `kpfftw` | 快速傅里叶变换 | 通过 `kpkml` 元包拉入 |
| 向量 | `kpvml` / `kpksvml` | 向量数学函数 | 通过 `kpkml` 元包拉入 |
| 其他 | `kpkupl` | 通用性能库 | 通过 `kpkml` 元包拉入 |
| 元包 | `kpkml` | 聚合上述子库 | `depends_on("kpkml compiler_variant=gcc", when="%gcc")` |

## 脚本

`install_batch.sh` — 读取清单，对 spack 中已有的包执行安装。

```bash
bash install_batch.sh              # 安装全部
bash install_batch.sh gcc          # 只装 gcc 版本
bash install_batch.sh bisheng      # 只装 bisheng 版本
bash install_batch.sh <包名>        # 只装指定包
bash install_batch.sh --from-3.5   # 处理 stage3.5 回传的包
```

## HPCKit 环境加载（仅手动编译时使用，即 stage3.5）

```bash
HPCKIT_PREFIX=$(spack location -i hpckit)
HPCKIT_VER=$(ls ${HPCKIT_PREFIX}/HPCKit/ | head -1)

# GCC 版本（加载 GCC + HMPI + KML）
cd ${HPCKIT_PREFIX}/HPCKit/${HPCKIT_VER} && source setvars.sh --use-gcc

# BiSheng 版本（加载 BiSheng + HMPI + KML）
cd ${HPCKIT_PREFIX}/HPCKit/${HPCKIT_VER} && source setvars.sh
```

**注意：写 package.py 时不需要 source setvars.sh，用 depends_on 即可。**

## 输出

| 文件 | 说明 |
|------|------|
| `install_log.md` | 安装日志（包名/编译器/版本/hash/状态/方式/重试次数/备注） |
| `handoff_to_3.5.md` | 移交清单（转 stage3.5 的失败包） |
| `$(get_local_repo_path)/packages/*/package.py` | 自编写 + 复制修改的 spack 包脚本 |
| `$SPACK_WORKFLOW_DIR/manual-build/*/build.sh` | 手动编译脚本（stage3.5 产出） |

## 失败处理

1. spec 解析失败 → 简化 variant 重试
2. 编译失败 → 检查 package.py 的 depends_on 是否正确、是否缺少 aarch64 适配
3. package.py 修改3次仍失败 → 写入 handoff_to_3.5.md，转 stage3.5
4. stage3.5 手动编译成功但 package.py 写不出（2次）→ 记录 ❌ 失败，跳过
5. stage3.5 手动编译也失败（3次）→ 记录 ❌ 失败，跳过

## Agent 契约

| 项目 | 值 |
|------|-----|
| 允许动作 | `spack spec`/`install`/`find`/`info`、复制官方 package.py 到本地 repo、编写 package.py、`source setvars.sh`（仅 stage3.5） |
| 禁止动作 | 改官方 repo 中的原始 recipe、改 kp*/hmpi 包、写 package.py 时 source setvars.sh |
| 输入 | `packages_to_install.yaml` + `handoff_to_3.md`（可选） |
| 输出 | `install_log.md` + `handoff_to_3.5.md`（可选） + package.py |
| 失败策略 | 路径A2/B 各3次重试 → stage3.5 手动编译3次 → 路径C 2次重试 → 失败跳过 |
| 参考文档 | `docs/spack-new-package/SKILL.md` + `docs/spack-new-package/references/`（全量知识库，10 个 reference）+ `docs/spack_package_guide.md`（速查）+ `AI_INSTRUCTION.md` + `stage3.5-manual-build/AI_INSTRUCTION.md` |
