# 阶段 3.5 AI 指令 (AI_INSTRUCTION.md)

> 本文件是给 AI Agent 的可直接执行指令。
> 读取 stage3 移交清单后，对每个失败的包执行手动编译。
> **手动编译成功后将编译命令回传给 stage3，由 stage3 据此编写 package.py。**

---

## 指令

你是鲲鹏920F HPC 软件栈部署工作流的阶段3.5执行 Agent。
你的任务是：对在阶段3中 spack 安装3次重试均失败的包，通过手动编译安装，并提取编译命令回传阶段3。

> ⛔ **禁止自行修改任何 .md 文件**（如 DESCRIPTION.md、AI_INSTRUCTION.md 等）。
> 如需修改，必须先向用户说明并获同意。脚本（manual_build.sh）自动生成的 .md 不受此限。
> 🔒 **禁止修改指令文件**：AI_INSTRUCTION.md 和 DESCRIPTION.md 是工作流的固定指令定义，无论执行成功或失败，都不得以任何理由修改、追加、删除其内容。每次工作流执行完毕后，指令文件必须与执行前完全一致。

### 前置条件

- Spack 环境已加载（推荐用工作流统一入口，会一并隔离 user scope）：
```bash
source /home/zhangyuhang/workflow/scripts/spack-env.sh
```
- 阶段3已完成，且 `handoff_to_3.5.md` 存在并包含至少 1 个失败的包
- HPCKit 已安装（`spack find hpckit` 成功）

### 输入文件

`/home/zhangyuhang/workflow/stage3-install/handoff_to_3.5.md`

格式：

| 包名 | 编译器 | 版本 | spec | 失败原因 | 源码URL | 本地package.py |
|------|--------|------|------|---------|---------|---------------|

### 参考文档

- HPCKit 环境加载：`stage3-install/DESCRIPTION.md` 中的「HPCKit 环境加载」章节
- 源码适配方法：`docs/spack_package_guide.md`
- HPCKit 生态已知坑：`docs/failure_handling.md` 中的「HPCKit 生态已知坑」章节
- 鲲鹏920 SVE 优化注意事项：`stage4-compile-opt/DESCRIPTION.md` 中的相关章节

### 执行方式

直接运行脚本初始化环境：

```bash
bash /home/zhangyuhang/workflow/stage3.5-manual-build/manual_build.sh
```

脚本会自动读取移交清单、加载 HPCKit 环境、创建构建目录。
然后按下面的手动步骤逐个包处理。

### 手动编译流程（每个包）

对移交清单中的每个包，按以下流程执行：

```
步骤 1：加载 HPCKit 环境
  │
  ▼
步骤 2：下载源码
  │
  ▼
步骤 3：分析构建系统
  ├── CMakeLists.txt → CMake 流程
  ├── configure/configure.ac → Autotools 流程
  ├── Makefile → Makefile 流程
  └── 其他 → 自定义流程
  │
  ▼
步骤 4：源码适配（aarch64）
  ├── 搜索 -mcmodel=medium/-m64/-msse/-mavx → 替换/删除
  ├── 检查 config.guess 是否支持 aarch64 → 替换
  ├── 检查 x86 内联汇编/SIMD → 条件编译/sse2neon
  └── 检查 Fortran 兼容性 → 加 -fallow-argument-mismatch
  │
  ▼
步骤 5：编译安装
  ├── cmake -DCMAKE_INSTALL_PREFIX=<prefix> ... && make -j$(nproc) && make install
  └── ./configure --prefix=<prefix> ... && make -j$(nproc) && make install
  │
  ├── 成功 → 步骤 6
  └── 失败 → 分析错误 → 修复 → 重试（回到步骤5，最多3次）
      └── 3次均败 → 记录 ❌，跳过该包
  │
  ▼
步骤 6：验证安装
  ├── make check / make test（如有）
  └── <binary> --version（冒烟测试）
  │
  ▼
步骤 7：提取编译命令并回传
  ├── 从构建过程中提取关键命令
  ├── 写入 handoff_to_3.md
  └── 保存 build.sh
```

### HPCKit 环境加载

```bash
HPCKIT_PREFIX=$(spack location -i hpckit)
HPCKIT_VER=$(ls ${HPCKIT_PREFIX}/HPCKit/ | head -1)

# GCC 版本（加载 GCC + HMPI + KML）
cd ${HPCKIT_PREFIX}/HPCKit/${HPCKIT_VER} && source setvars.sh --use-gcc

# BiSheng 版本（加载 BiSheng + HMPI + KML）
cd ${HPCKIT_PREFIX}/HPCKit/${HPCKIT_VER} && source setvars.sh
```

### 构建目录结构

每个包的构建目录：

```
$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/
├── src/              # 源码
├── build/            # 构建中间产物（CMake out-of-source）
├── install/          # 安装前缀
└── build.sh          # 构建脚本（保存成功的编译命令）
```

### 编译命令提取规则

手动编译成功后，提取以下信息写入 `handoff_to_3.md`：

1. **configure/cmake 参数**：所有 `-D` 参数、`--prefix`、`--with-*` 等
2. **编译器 flag**：CFLAGS/CXXFLAGS/FFLAGS 中非默认的 flag
3. **依赖路径**：手动指定的库路径（`-L`、`-I`、`PKG_CONFIG_PATH`）
4. **环境变量**：非默认的环境变量设置
5. **patch 操作**：对源码做了哪些修改

示例：

```markdown
| myapp | gcc | 1.0 | cmake -DCMAKE_C_COMPILER=gcc -DCMAKE_INSTALL_PREFIX=/path/install -DMPI_C_COMPILER=mpicc -DOPENMP=ON CFLAGS="-O3 -mcpu=tsv110" | /path/install | /path/build.sh |
```

### 回传文件格式

`handoff_to_3.md`（由 manual_build.sh 自动生成，AI Agent 填充内容）：

```markdown
# Stage3.5 → Stage3 回传清单

> 由 manual_build.sh 自动生成。
> 以下包在 stage3.5 中手动编译成功，编译命令已提取，需 stage3 据此编写 package.py。

| 包名 | 编译器 | 版本 | 编译命令 | 安装路径 | 构建脚本 |
|------|--------|------|---------|---------|---------|
```

### 重试规则

| 项目 | 规则 |
|------|------|
| 每包最多重试 | 3 次 |
| 每次重试允许 | 修改构建参数、修改编译器 flag、修改源码适配 aarch64、切换构建系统 |
| 3次均败 | 记录 ❌ 到 `manual_build_log.md`，跳过该包 |
| 不允许 | 放弃编译、伪造结果 |

### 鲲鹏920 SVE 优化注意事项

手动编译时注意以下已知问题（实测经验；全量见 `docs/spack-new-package/SKILL.md` 阶段十 + `references/kalign-sve-optimization.md`、`references/hmpi-ompi-cc-debugging.md`）：

| 问题 | 后果 | 规避 |
|------|------|------|
| -flto 禁用 GCC SVE 向量化 | SVE 指令消失 | 不要加 -flto |
| -ffast-math 破坏浮点收敛循环 | 程序挂起/崩溃 | GCC 默认 FP 语义最优，不设 -ffast-math |
| config.guess 不识别 aarch64 | configure 失败 | 用系统版本覆盖 |
| x86 SIMD 代码 | 编译失败 | 引入 sse2neon.h 或条件编译 |
| hmpi 的 mpicc 用裸 gcc | 链接错误 | 设置 OMPI_CC 指向正确的编译器 |

### 输出物

1. `handoff_to_3.md` — 回传给 stage3 的编译命令清单
2. `manual_build_log.md` — 手动编译日志
3. `$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/build.sh` — 每个包的构建脚本

### 完成标志

- 移交清单中的每个包都有记录（✅ 成功回传 或 ❌ 失败跳过）
- 所有成功的包的 `build.sh` 已保存
- `handoff_to_3.md` 包含所有成功包的编译命令
- `manual_build_log.md` 包含每个包的状态和重试次数

完成后，将 `handoff_to_3.md` 路径告知调度器，回到阶段3执行 package.py 编写。
