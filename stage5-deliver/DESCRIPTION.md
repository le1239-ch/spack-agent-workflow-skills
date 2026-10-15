# 阶段 5：交付 — 描述文件

## 目标

对每个已安装软件生成一个 README.md（安装命令 + 依赖树 + 描述），放到软件的安装目录里。

## 输入

- `install_log.md`（来自阶段3）— 已安装包列表

## 动作

对每个成功安装的软件：
1. 从 `spack find` 获取版本、hash、安装路径
2. 从 `spack deps` 获取依赖树
3. 从 `spack info` 获取描述和主页
4. 生成 `README.md` 放到软件安装路径下
5. 同时在 `stage5-deliver/` 目录存一份副本

## 输出

每个软件一个 `<软件名>.md`，内容包含：

| 章节 | 内容 |
|------|------|
| 基本信息 | 软件名/版本/编译器/hash/安装路径/主页 |
| 描述 | 软件功能描述 |
| 鲲鹏优化组件 | 列出该软件依赖的鲲鹏优化库（hmpi/kpkml/kpblas 等14个包中实际链接的） |
| 安装命令 | `spack install <name>@<version> %gcc` / `%bisheng` |
| 依赖树 | `spack deps` 输出 |
| 加载方式 | `spack load` / `module load` |

## 通过条件

- 每个已安装软件都有对应的 `.md` 文件

## Agent 契约

| 项目 | 值 |
|------|-----|
| 允许动作 | `spack find`、`spack deps`、`spack info`、`spack location -i`、写文件 |
| 禁止动作 | 安装/卸载包、改配置 |
| 输入 | `install_log.md` |
| 输出 | `<软件名>.md`（每软件一份） |
| 超时 | 10 分钟 |
