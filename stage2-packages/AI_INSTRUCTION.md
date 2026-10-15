# 阶段 2 AI 指令 (AI_INSTRUCTION.md)

> 本文件是给 AI Agent 的指令。

---

## 指令

你是阶段2执行 Agent。你的任务是协助用户填写待安装软件清单。

> ⛔ **禁止自行修改任何 .md 文件**（如 package_verification.md、DESCRIPTION.md 等）。如需修改，必须先向用户说明并获同意。脚本自动生成的 .md 不受此限。
> 🔒 **禁止修改指令文件**：AI_INSTRUCTION.md 和 DESCRIPTION.md 是工作流的固定指令定义，无论执行成功或失败，都不得以任何理由修改、追加、删除其内容。每次工作流执行完毕后，指令文件必须与执行前完全一致。

### 前置条件

- Spack 环境已加载：
```bash
source /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/share/spack/setup-env.sh
```
- 阶段1已完成

### 执行方式

1. 打开模板文件，根据用户需求编辑：
```bash
vi /home/zhangyuhang/workflow/stage2-packages/packages_to_install.yaml
```

2. 每行一个软件，格式：`软件名,版本(可选),编译器(gcc/bisheng/both)`

```
# gromacs                    # 注释示例，不会被执行
# lammps,20230802.4          # 注释示例，不会被执行
# openfoam,,gcc              # 注释示例，不会被执行
# cp2k,,bisheng              # 注释示例，不会被执行
elmerfem,9.0,both            # 实际要安装的软件
```

3. 可选：验证包名在 spack 中是否存在：
```bash
spack info <包名>    # 存在则直接进入阶段3
                     # 不存在则阶段3 Agent 会编写 package.py 或手动编译
```

4. 填写完成后进入阶段3：
```bash
# 正式流程：切到 stage3-install/AI_INSTRUCTION.md，由 Agent 按决策树逐个包执行
#   （stage3 指令明确要求「不要直接运行 install_batch.sh」）
# 批处理模式（无人交互/复现）才这样启动：
bash /home/zhangyuhang/workflow/stage3-install/install_batch.sh
```

### 重要规则

- 模板中 `#` 开头的行是注释/示例，**不会被执行**，不要验证或安装它们
- 只处理非注释、非空行的实际条目
- 示例条目仅展示格式用法，用户在 `# ── 在下方添加你的软件 ──` 下方添加的才是真实待安装软件

### 完成标志

`packages_to_install.yaml` 中至少有 1 个软件。
