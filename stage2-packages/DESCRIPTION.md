# 阶段 2：待安装软件清单（手动填写）— 描述文件

## 目标

用户在 `packages_to_install.yaml` 中手动填写本次工作流需要安装的软件。
**极简格式：每行一个软件，只填名称、版本（可选）、编译器（可选）。**

> 清单中的软件在阶段3安装时，会通过 `packages.yaml` 的 provider 配置自动链接鲲鹏数学库（kpkml/hmpi 等14个优化组件），无需在此手动指定。

## 输入

- 阶段1 配置完成

## 动作

用户手动编辑 `packages_to_install.yaml`，每行一个软件：

```
# 格式：软件名,版本(可选),编译器(gcc/bisheng/both)
gromacs                    # 装最新版，gcc+bisheng 都装
lammps,2Aug2023            # 装指定版本，gcc+bisheng 都装
openfoam,,gcc              # 装最新版，只装 gcc
cp2k,,bisheng              # 装最新版，只装 bisheng
```

## 输出

| 文件 | 说明 |
|------|------|
| `packages_to_install.yaml` | CSV 格式清单（软件名,版本,编译器） |

## 通过条件

- 清单中至少有 1 个软件

## Agent 契约

| 项目 | 值 |
|------|-----|
| 允许动作 | 编辑 `packages_to_install.yaml`、`spack info`（验证包名） |
| 禁止动作 | `spack install`（阶段3才装） |
| 输入 | 阶段1 配置完成 |
| 输出 | `packages_to_install.yaml` |
| 超时 | 无（手动操作） |
