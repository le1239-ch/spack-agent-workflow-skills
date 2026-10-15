# Stage3 → Stage3.5 移交清单

> 由 stage3 执行 Agent 生成（2026-10-09 本轮）。
> **本轮移交数量：0 —— 清单内 5 个软件的 2 个编译器版本共 10 个安装任务全部成功，无需 stage3.5 手动编译。**
> 因此 `stage3.5-manual-build/manual_build.sh` 本轮**不需要**运行。

| 包名 | 编译器 | 版本 | spec | 失败原因 | 源码URL | 本地package.py |
|------|--------|------|------|---------|---------|---------------|
| — | — | — | — | 无 | — | — |

## 上一轮内容的归档

原文件里残留的是**上一轮（2026-09-28，gromacs/namd 清单）**的 namd@3.0.3 移交行
（NAMD 源码包 license 门禁需 UIUC 账号，本机无 tarball）。该条与本轮清单
（fds/su2/cmaq/swan/roms）无关，已归档保留以免丢失：

- 归档：`handoff_to_3.5.md.prev-20261009-155404`（内容逐字节保留）
- 如需继续处理 namd：从该归档取回，或查看 `stage3-install/install_log.md` 的历史版本
- 回滚本文件：`cp -a handoff_to_3.5.md.prev-20261009-155404 handoff_to_3.5.md`

## 本轮安装结果速查（详见 `install_log.md`）

| 包 | gcc | bisheng(%llvm) |
|----|-----|----------------|
| fds | ✅ 2jvgrgl | ✅ wvwdedm |
| su2 | ✅ z6rrgml | ✅ 3cjzmva |
| cmaq | ✅ mznbwiz（仅源码分发） | ✅ 4ekbrka（仅源码分发） |
| swan | ✅ wlwzozz | ✅ yjxoulh |
| roms | ✅ xq4bdvx | ✅ ahn6fxj |
