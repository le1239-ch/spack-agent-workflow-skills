# 阶段 3.5：手动编译兜底 — 描述文件

## 目标

对在阶段3中 spack 安装（含 package.py 3次重试）失败的包，通过手动编译安装。
手动编译成功后，提取编译命令回传给阶段3，由阶段3据编译命令编写 package.py。

> **此阶段是阶段3的兜底，不是独立阶段。** 只有阶段3产生移交清单时才执行。

## 输入

- `stage3-install/handoff_to_3.5.md`（来自阶段3）— 移交清单

移交清单格式：

| 包名 | 编译器 | 版本 | spec | 失败原因 | 源码URL | 本地package.py |
|------|--------|------|------|---------|---------|---------------|

## 动作清单

### 步骤 3.5.1 读取移交清单

读取 `handoff_to_3.5.md`，获取需要手动编译的包列表。

### 步骤 3.5.2 加载 HPCKit 环境

根据编译器类型加载 HPCKit 环境（仅手动编译时使用 `source setvars.sh`）：

```bash
HPCKIT_PREFIX=$(spack location -i hpckit)
HPCKIT_VER=$(ls ${HPCKIT_PREFIX}/HPCKit/ | head -1)

# GCC 版本
cd ${HPCKIT_PREFIX}/HPCKit/${HPCKIT_VER} && source setvars.sh --use-gcc

# BiSheng 版本
cd ${HPCKIT_PREFIX}/HPCKit/${HPCKIT_VER} && source setvars.sh
```

### 步骤 3.5.3 手动编译（每包最多 3 次重试）

对移交清单中的每个包：

1. 创建构建目录：`$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/`
2. 下载/克隆源码
3. 分析构建系统（CMake / Autotools / Makefile / ...）
4. 执行编译安装（`./configure && make && make install` 或等价命令）
5. 安装到 `$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/install`
6. 验证安装（`make check` 或 `--version`）
7. 如失败，分析错误，修复后重试（最多 3 次）

### 步骤 3.5.4 提取编译命令并回传

手动编译成功后：

1. 从构建过程中提取关键编译命令（configure 参数、make 参数、编译器 flag）
2. 写入 `handoff_to_3.md`（回传给阶段3）
3. 保存构建脚本到 `$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/build.sh`

回传清单格式：

| 包名 | 编译器 | 版本 | 编译命令 | 安装路径 | 构建脚本 |
|------|--------|------|---------|---------|---------|

### 步骤 3.5.5 处理失败

如果手动编译 3 次均失败：

- 记录到 `manual_build_log.md`（状态 ❌）
- 该软件标记为失败，不回传阶段3
- 继续处理下一个包

## 重试规则

| 阶段 | 最多重试次数 | 失败后动作 |
|------|------------|----------|
| 手动编译 | 3 次 | 记录失败，跳过该包 |

每次重试允许的修复动作：
- 修改 configure/cmake 参数
- 修改编译器 flag（如去掉 -flto、加 -fallow-argument-mismatch）
- 修改源码适配 aarch64（如删除 x86 SIMD、替换 config.guess）
- 切换构建系统（如 Autotools → CMake）

## 输出

| 文件 | 说明 |
|------|------|
| `handoff_to_3.md` | 回传清单（编译命令 → 阶段3编写 package.py） |
| `manual_build_log.md` | 手动编译日志（包名/编译器/状态/重试次数/编译命令） |
| `$SPACK_WORKFLOW_DIR/manual-build/<pkg_name>/build.sh` | 每个包的构建脚本 |

## 流程图

```
handoff_to_3.5.md（来自 stage3）
  │
  ▼
读取移交清单
  │
  ▼
对每个包：
  ├── 加载 HPCKit 环境（source setvars.sh）
  ├── 下载源码 → 分析构建系统
  ├── 手动编译安装（重试1/2/3）
  │   ├── 成功 → 提取编译命令 → 写入 handoff_to_3.md → 回传 stage3
  │   └── 3次均败 → 记录 ❌ → 跳过
  └── 保存 build.sh
  │
  ▼
handoff_to_3.md → stage3 据此编写 package.py（2次机会）
```

## Agent 契约

| 项目 | 值 |
|------|-----|
| 脚本 | `stage3.5-manual-build/manual_build.sh` |
| AI 指令 | `stage3.5-manual-build/AI_INSTRUCTION.md` |
| 允许动作 | `source setvars.sh`、下载源码、`./configure`/`cmake`/`make`、写构建脚本、写 handoff 文件 |
| 禁止动作 | 改官方 spack recipe、改 kp*/hmpi 包、`spack install`（本阶段不用 spack 安装） |
| 输入 | `stage3-install/handoff_to_3.5.md` |
| 输出 | `handoff_to_3.md` + `manual_build_log.md` + `build.sh` |
| 失败策略 | 每包最多 3 次重试，仍失败则记录跳过 |
| 超时 | 每包 1 小时 |
