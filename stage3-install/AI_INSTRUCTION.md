# 阶段 3 AI 指令 (AI_INSTRUCTION.md)

> 本文件是给 AI Agent 的可直接执行指令。
> 读取 `packages_to_install.yaml` 清单后，对每个软件按编译器（gcc/bisheng）安装。
> **包可能不存在于 spack，Agent 需要自行编写 package.py。**
> **安装失败时最多修改重试 3 次，仍失败则转交 stage3.5 手动编译。**

---

## 指令

你是鲲鹏920F HPC 软件栈部署工作流的阶段3执行 Agent。
你的任务是：读取待安装清单，对每个软件用指定编译器安装成功，输出对应的 package 脚本。

> ⛔ **禁止自行修改任何 .md 文件**（如 install_log.md、DESCRIPTION.md 等）。
> 如需修改，必须先向用户说明并获同意。脚本自动生成的 .md 不受此限。
> **例外**：`install_log.md` 视为 Agent 维护的日志文件，Agent 有责任在每次安装尝试后更新它（等同脚本自动维护）。
> 🔒 **禁止修改指令文件**：AI_INSTRUCTION.md 和 DESCRIPTION.md 是工作流的固定指令定义，无论执行成功或失败，都不得以任何理由修改、追加、删除其内容。每次工作流执行完毕后，指令文件必须与执行前完全一致。

### 编译器名称映射（重要！）

清单中的编译器名称与 spack 的 `%compiler` 名称不同：

| 清单中的名称 | spack 的 %compiler 名称 | 说明 |
|-------------|------------------------|------|
| `gcc` | `%gcc` | 直接对应 |
| `bisheng` | **`%llvm`** | BiSheng 在 spack 中注册名为 `llvm`，**不是 `%bisheng`** |
| `both` | 分别用 `%gcc` 和 `%llvm` 安装 | 拆成两次安装 |

> ⚠ 在所有 spack 命令中，bisheng 编译器一律用 `%llvm`，不要用 `%bisheng`（spack 不认识）。

### 执行方式

Agent 应按下方决策树逻辑**自行逐个执行 spack 命令**（不直接运行 install_batch.sh）。
`install_batch.sh` 仅作为 batch 模式的可选辅助工具和逻辑参考。
Agent 每完成一次安装尝试（成功或失败），须将结果记录到 `install_log.md`。

### 前置条件

- Spack 环境已加载（**推荐用工作流统一入口，它会一并隔离 user scope**）：
```bash
source /home/zhangyuhang/workflow/scripts/spack-env.sh
```
- 阶段1已完成（spack 可用、hpckit 安装、gcc+bisheng 编译器已注册）
- `packages_to_install.yaml` 已由用户填写

### 输入文件

`/home/zhangyuhang/workflow/stage2-packages/packages_to_install.yaml`

格式：每行一个软件，`软件名,版本(可选),编译器(gcc/bisheng/both)`，整行 `#` 开头为注释。
⚠ 不要写行尾注释（脚本虽会剥离行尾 `#`，但说明请单独成行，避免踩坑）。

### 参考文档

- **Spack 打包知识库（工作流内全量副本，权威，优先查这里）**：`/home/zhangyuhang/workflow/docs/spack-new-package/`
  - `SKILL.md` — 总纲：阶段一~十一完整写包流程（构建系统分析 / 基类选择 / HPCKit 双编译器模板 / 版本·变体·depends_on 声明 / 构建逻辑 / 环境注入 / patch / 本地 repo 注册与验证 / 命名规则 / 实战案例索引 / 关键规则速查）
  - `references/cmake-cross-compiler-install-pitfalls.md` — CMake 项目 gcc/llvm 双编译器安装陷阱（openblas `all`→`shared` 跳过 aarch64 SIGABRT 测试、GCC 12+ DO 循环变量、Flang 跨编译器 `.mod` 不兼容、FindMKL）
  - `references/kml-library-structure-and-merging.md` — KML 库结构与合并（链接 KML 失败时看）
  - `references/kml-stdout-warning-pollution.md` — KML stdout 警告污染 meson `run_command`
  - `references/hmpi-ompi-cc-debugging.md` — hmpi 缺 OMPI_CC 注入 → mpicc 回退裸 gcc（含 A/B 对照复现）
  - `references/spack-package-verification-gotchas.md` — 包名/版本验证陷阱（通用名 ≠ spack 名、builtin 版本滞后上游、manual_download 包）
  - `references/packages-yaml-config-gotchas.md` — packages.yaml 多值变体 require 语法、`all.compiler` 已废弃、hpckit 版本约束冲突
- Spack package.py 编写速查（精简版，源自上述知识库）：`/home/zhangyuhang/workflow/docs/spack_package_guide.md`
- HPCKit 生态已知坑：同上文件第 12 节 + `docs/failure_handling.md`
- Stage3.5 手动编译兜底：`stage3.5-manual-build/AI_INSTRUCTION.md`

### 完整执行流程

对清单中的每个软件、每个编译器版本，按以下决策树执行：

```
软件在 spack 中存在？（spack info <name>）
│
├── 是 → 路径A：直接安装已有包
│   │
│   ├── spack install <name>@<version> %<compiler>
│   │   ├── 成功 → 记录 install_log.md ✅ → stage4
│   │   └── 失败 → 路径A2：复制+修改已有 package.py
│   │       │
│   │       ├── 复制官方 package.py + 补丁文件到本地 repo
│   │       │   （从 spack builtin/kunpeng920prof repo 复制到 get_local_repo_path()/packages/<name>/）
│   │       ├── 修改 package.py（修复编译错误/适配 aarch64/调整依赖）
│   │       ├── spack spec <name>@<version> %<compiler>  验证
│   │       ├── spack install <name>@<version> %<compiler>
│   │       │   ├── 成功 → 记录 ✅（package.py modified）→ stage4
│   │       │   └── 失败 → 修改重试（重试1）
│   │       │       ├── 修改 → spack install（重试2）
│   │       │       │   ├── 成功 → ✅ → stage4
│   │       │       │   └── 失败 → 修改 → spack install（重试3）
│   │       │       │       ├── 成功 → ✅ → stage4
│   │       │       │       └── 失败 → 写入 handoff_to_3.5.md → 转 stage3.5
│   │       │       └（共3次修改重试机会）
│   │       │
│   │       └── 注意：不得修改官方 repo 中的原始 package.py，
│   │           只修改复制到本地 repo 的副本
│   │
├── 否 → 路径B：分析源码编写新 package.py
│   │
│   ├── git clone 源码到 /tmp，分析构建系统（CMake/Autotools/Makefile/...）
│   ├── 参考 docs/spack_package_guide.md 编写 package.py
│   ├── 在 package.py 中用 depends_on 声明 HPCKit 依赖：
│   │     depends_on("hpckit", type="build")
│   │     depends_on("hmpi compiler_variant=gcc", when="%gcc", type=("build","link","run"))
│   │     depends_on("hmpi compiler_variant=bisheng", when="%llvm", type=("build","link","run"))
│   │     depends_on("kpkml compiler_variant=gcc", when="%gcc", type=("build","link","run"))
│   │     depends_on("kpkml compiler_variant=bisheng", when="%llvm", type=("build","link","run"))
│   ├── 放入本地 repo：$(get_local_repo_path)/packages/<pkg_name>/package.py
│   ├── repo 由 create_local_repo() 创建并注册，无需重复 spack repo add
│   ├── spack spec <name>@<version> %<compiler>  验证
│   ├── spack install <name>@<version> %<compiler>
│   │   ├── 成功 → 记录 ✅（package.py new）→ stage4
│   │   └── 失败 → 修改 package.py 重试（重试1/2/3）
│   │       ├── 任一成功 → ✅ → stage4
│   │       └── 3次均败 → 写入 handoff_to_3.5.md → 转 stage3.5
│   │
│   └── 注意：共3次修改重试机会（含首次共4次安装尝试）
│
└── stage3.5 回传处理（路径C）：
    │
    ├── 读取 stage3.5-manual-build/handoff_to_3.md
    ├── 对每个手动编译成功的包，根据编译命令编写 package.py
    ├── spack spec 验证 → spack install
    │   ├── 成功 → 记录 ✅（package.py from manual）→ stage4
    │   └── 失败 → 修改重试（重试1）
    │       ├── 修改 → spack install（重试2）
    │       │   ├── 成功 → ✅ → stage4
    │       │   └── 失败 → ❌ 失败，跳过该软件 → stage4
    │       └（共2次修改重试机会）
    │
    └── 注意：手动编译成功但 package.py 2次写不出 → 算失败跳过
```

### 重试规则汇总

| 阶段 | 路径 | 首次 | 修改重试次数 | 全部失败后 |
|------|------|------|------------|----------|
| Stage3 | A（已有包直接装） | 1次安装 | — | 转 A2 |
| Stage3 | A2（复制+修改已有package.py） | 1次安装 | 3次 | 转 stage3.5 |
| Stage3 | B（新写package.py） | 1次安装 | 3次 | 转 stage3.5 |
| Stage3.5 | 手动编译 | 1次编译 | 3次 | ❌ 失败跳过 |
| Stage3 | C（据手动编译命令写package.py） | 1次安装 | 2次 | ❌ 失败跳过 |

**根因明确的额外尝试条款**：如果在重试次数耗尽后，Agent 发现了与之前所有尝试不同的根因（例如：跨编译器 .mod 文件不兼容 → 需要强制同编译器依赖 `^netcdf-fortran %llvm`），且修复方案明确不同于之前的尝试，允许进行 1 次额外尝试。额外尝试仍失败则转 stage3.5。

### 关键规则：HPCKit 依赖注入方式

**spack package.py 方式**：用 `depends_on` 声明依赖，spack 自动处理编译器/MPI/KML 的注入。

```python
# package.py 中声明依赖（不需要手动 source setvars.sh）
depends_on("hpckit", type="build")
depends_on("hmpi compiler_variant=gcc", when="%gcc", type=("build","link","run"))
depends_on("hmpi compiler_variant=bisheng", when="%llvm", type=("build","link","run"))
depends_on("kpkml compiler_variant=gcc", when="%gcc", type=("build","link","run"))
depends_on("kpkml compiler_variant=bisheng", when="%llvm", type=("build","link","run"))
```

**鲲鹏数学库及优化组件 depends_on 速查（14个包）**：

| 类别 | 包名 | 功能 | 声明方式 |
|------|------|------|----------|
| MPI | `hmpi` | 鲲鹏优化MPI | 单独 depends_on |
| 套件 | `hpckit` | HPC开发套件元包 | 单独 depends_on |
| BLAS | `kpblas` / `kpspblas` | 基础/稀疏BLAS | 通过 `kpkml` 元包拉入 |
| LAPACK | `kplapack` / `kpscalapack` / `kpscasolver` / `kpsolver` | LAPACK系列 | 通过 `kpkml` 元包拉入 |
| FFT | `kpfft` / `kpfftw` | 快速傅里叶变换 | 通过 `kpkml` 元包拉入 |
| 向量 | `kpvml` / `kpksvml` | 向量数学函数 | 通过 `kpkml` 元包拉入 |
| 其他 | `kpkupl` | 通用性能库 | 通过 `kpkml` 元包拉入 |
| 元包 | `kpkml` | 聚合上述子库的统一入口 | 单独 depends_on |

> **常用做法**：直接 `depends_on("kpkml ...")` 即可拉入全部 KML 子组件，无需逐个声明 kpblas/kplapack 等。`hmpi` 和 `hpckit` 需单独声明。

**手动编译方式**（stage3.5）：才需要 `source setvars.sh`，不在 package.py 中混用 depends_on。

### 路径A2：复制官方 package.py 到本地 repo

当已有包安装失败时，复制官方 package.py 和补丁文件到本地 repo 进行修改：

```bash
LOCAL_REPO=$(get_local_repo_path)

# 找到官方 package.py 路径
# ⚠ 不要用 ${SPACK_DIR}/var/spack/repos/builtin —— spack 1.2.1 没有该目录（builtin 由
#   bootstrap 副本提供），硬编码该路径永远找不到包。用 spack 自己解析即可：
OFFICIAL_PKG_DIR=$(spack location -p <pkg_name> 2>/dev/null | head -1)
[ -z "$OFFICIAL_PKG_DIR" ] && OFFICIAL_PKG_DIR=$(find ${KP_SPACK_REPO_DIR} \
    -name "package.py" -path "*/<pkg_name>/*" 2>/dev/null | head -1 | xargs dirname)

# 复制 package.py 和补丁文件到本地 repo
mkdir -p ${LOCAL_REPO}/packages/<pkg_name>
cp ${OFFICIAL_PKG_DIR}/package.py ${LOCAL_REPO}/packages/<pkg_name>/
cp ${OFFICIAL_PKG_DIR}/*.patch ${LOCAL_REPO}/packages/<pkg_name>/ 2>/dev/null || true
cp -r ${OFFICIAL_PKG_DIR}/* ${LOCAL_REPO}/packages/<pkg_name>/ 2>/dev/null || true

# 验证本地 repo 中的包可见（本地 repo 优先级高于 builtin）
spack info <pkg_name>

# 修改本地 repo 中的 package.py（不碰官方原始文件）
# 常见修改：
#   - 修复 variant 不兼容
#   - 添加 aarch64 适配 patch
#   - 调整 depends_on 版本约束
#   - 添加 HPCKit 依赖声明

# 修改后重新安装
spack spec <name>@<version> %<compiler>
spack install <name>@<version> %<compiler>
```

### 路径B：编写全新 package.py

```bash
# 创建 package.py 目录
LOCAL_REPO=$(get_local_repo_path)
mkdir -p ${LOCAL_REPO}/packages/<pkg_name>

# 放入 package.py
cp /tmp/<pkg_name>/package.py ${LOCAL_REPO}/packages/<pkg_name>/package.py

# repo 已由 create_local_repo 注册到 spack，无需 spack repo add
# 验证包可见
spack info <pkg_name>
```

### 移交 stage3.5

当路径A2或路径B的3次重试均失败时，写入移交清单：

```bash
# 追加到 handoff_to_3.5.md
HANDOFF_FILE="${SCRIPT_DIR}/handoff_to_3.5.md"

# 如文件不存在则创建表头
if [ ! -f "$HANDOFF_FILE" ]; then
    cat > "$HANDOFF_FILE" << 'EOF'
# Stage3 → Stage3.5 移交清单

> 由 install_batch.sh 自动生成。
> 以下包在 stage3 中 spack 安装3次重试均失败，需 stage3.5 手动编译。

| 包名 | 编译器 | 版本 | spec | 失败原因 | 源码URL | 本地package.py |
|------|--------|------|------|---------|---------|---------------|
EOF
fi

# 追加失败包信息
echo "| <pkg_name> | <compiler> | <version> | <spec> | <最后错误摘要> | <源码URL> | <本地package.py路径或无> |" >> "$HANDOFF_FILE"
```

然后执行：

```bash
bash /home/zhangyuhang/workflow/stage3.5-manual-build/manual_build.sh
```

### 路径C：处理 stage3.5 回传

当 stage3.5 手动编译成功并回传编译命令后（`handoff_to_3.md` 存在），据编译命令编写 package.py：

```bash
# 读取回传清单
cat stage3.5-manual-build/handoff_to_3.md

# 对每个包：
# 1. 根据编译命令（configure/cmake 参数、编译器 flag）编写 package.py
# 2. 放入本地 repo
# 3. spack spec 验证
# 4. spack install
#    ├── 成功 → ✅（package.py from manual）→ stage4
#    └── 失败 → 修改重试（最多2次）
#        └── 2次均败 → ❌ 失败，跳过该软件 → stage4
```

### 输出物

对每个软件，记录到 `install_log.md`：

```markdown
| 包名 | 编译器 | 版本 | hash | 状态 | 方式 | 重试次数 | 备注 |
|------|--------|------|------|------|------|---------|------|
| gromacs | gcc | 2023.3 | abc1234 | ✅ 成功 | builtin | 0 | — |
| my-app | gcc | 1.0 | def5678 | ✅ 成功 | package.py new | 1 | 首次spec失败，加patch后成功 |
| elmerfem | gcc | 9.0 | — | ✅ 成功 | package.py modified | 2 | 复制官方+修改variant |
| my-app2 | bisheng | 2.0 | — | ✅ 成功 | package.py from manual | 1 | stage3.5手动编译成功后回传 |
| broken-app | gcc | 1.0 | — | ❌ 失败 | — | 3+3+2 | stage3.5手动编译成功但package.py写不出 |
```

同时保存所有编写的 package.py 和构建脚本到：
- `$(get_local_repo_path)/packages/<pkg_name>/package.py`
- `$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/build.sh`（stage3.5 产出）

### 失败处理

1. **spec 解析失败** → 简化 variant/constraints 重试
2. **编译失败** → 检查 package.py 的 depends_on 是否正确、是否缺少 aarch64 适配
3. **package.py 修改3次仍失败** → 写入 handoff_to_3.5.md，转 stage3.5
4. **stage3.5 手动编译成功但 package.py 写不出（2次）** → 记录 ❌ 失败，跳过
5. **stage3.5 手动编译也失败（3次）** → 记录 ❌ 失败，跳过

### 完成标志

- `install_log.md` 中清单内每个软件的每个编译器版本都有记录（✅ 或 ❌）
- `install_log.md` 中不残留模板示例数据（gromacs/lammps/my-app 等示例行须清除）
- 所有自定义 package.py 已保存到本地 repo `$(get_local_repo_path)/packages/`
- 如有移交，`handoff_to_3.5.md` 和 `handoff_to_3.md` 已正确填充
- 所有手动构建脚本已保存到 `$SPACK_WORKFLOW_DIR/manual-build/`
