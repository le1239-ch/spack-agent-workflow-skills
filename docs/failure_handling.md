# 失败处理策略

## 概述

本工作流的失败处理遵循"快速失败、记录跳过、不阻塞后续"的原则。

## 重试规则（Stage3 + Stage3.5）

| 路径 | 场景 | 修改重试次数 | 全部失败后 |
|------|------|------------|----------|
| A2 | 已有包安装失败→复制+修改官方 package.py | 3 次 | 转 stage3.5 |
| B | 包不存在→新写 package.py | 3 次 | 转 stage3.5 |
| 3.5 | 手动编译（source setvars.sh + configure/make） | 3 次 | ❌ 失败跳过 |
| C | 据手动编译命令写 package.py | 2 次 | ❌ 失败跳过（手动编译成功但package.py写不出=失败） |

### 允许的修复动作

| 序号 | 动作 | 示例 | 适用场景 |
|------|------|------|----------|
| 1 | 换 variant | `cp2k+mpi+libint+libxc` → `cp2k+mpi+libxc` | variant 导致的编译错误 |
| 2 | 加 `^` 约束 | `netcdf-c+mpi ^hdf5@1.14` | 依赖版本不兼容 |
| 3 | 修改复制的 package.py | 复制官方→本地 repo→修改 depends_on/variant/patch | 已有包安装失败 |
| 4 | 新写 package.py | 分析源码+GitHub文档→编写 | 包不存在 |
| 5 | 手动编译修复 | 修改 configure 参数/编译器 flag/源码适配 aarch64 | stage3.5 手动编译 |

### 不允许的动作

- 修改官方 spack recipe（`builtin/packages/` 下的原始 `package.py`）
- 修改 kp* / hmpi 等基础设施数学库包
- 并行安装同一批次的包
- 跨批次混装
- 重新编译底层框架（spack 包本身）

## 编译优化失败处理

| 失败类型 | 处理方式 |
|----------|----------|
| `--fresh` 重编失败 | 去掉 `^kpblas ^kplapack` 约束重试 1 次 |
| spec 解析失败 | 简化 spec（去掉部分 variant） |
| 编译器不兼容 | 落回 `%gcc`（从 `%bisheng`） |
| KML 链接失败 | 使用 OpenBLAS 作为 fallback |

## 运行时调优失败处理

| 失败类型 | 处理方式 |
|----------|----------|
| benchmark 不存在 | 记录并跳过，运行 `--version` 作为冒烟测试 |
| 运行超时（>300s） | 记录超时，减小问题规模后重试 |
| 数值结果不一致 | 回退到基线配置，不应用优化 |
| NUMA 绑核失败 | 使用 `--bind-to core` 替代 `numactl` |

## 环境问题处理

| 问题 | 诊断 | 修复 |
|------|------|------|
| spack 不在 PATH | `which spack` | `source <spack>/share/spack/setup-env.sh` |
| BiSheng 未注册 | `spack compiler list` | `spack compiler find --scope=site /path/to/bisheng/bin` |
| KML repo 未挂载 | `spack repo list` | `spack repo add /path/to/kml-repo` |
| HMPI mpicc 失败 | `mpicc --showme` | `export OPAL_PREFIX=<hmpi_path>` |
| BLAS 链接错误 | `spack spec <pkg> \| grep blas` | `spack install <pkg> ^kpblas ^kplapack`（勿用 `require: kpkml`，实测毒行） |
| lib not found (运行时) | `ldd <binary> \| grep "not found"` | `spack load <pkg>` 或手动设 `LD_LIBRARY_PATH` |

## HPCKit 生态已知坑（基于 spack-new-package skill；全量见 `docs/spack-new-package/SKILL.md` 阶段十 + `docs/spack-new-package/references/`）

| 坑 | 后果 | 规避 |
|----|------|------|
| hmpi 缺少 OMPI_CC 注入 | mpicc 用裸 gcc 而非 spack wrapper | 消费者包自行设 OMPI_CC=spack_cc |
| spack compiler-wrapper 静默禁用 SVE | 传了 `-mcpu=native` 却 0 条 SVE 指令 | 绕过 wrapper：`CC`/`CXX` 设为 HPCKit gcc 绝对路径 |
| -flto 禁用 GCC SVE 向量化 | SVE 指令消失 | 不要加 -flto |
| -ffast-math 破坏浮点收敛循环 | 程序挂起/崩溃 | GCC 默认 FP 语义最优 |
| KML stdout 警告污染 meson | run_command 输出含警告 | meson native file [properties] 提供 external property |
| 包名含 `-` 的 libs/headers 失败 | spack 把 `-` 当 glob `?` | 用 `spec["pkg-opt"].prefix` 拼路径 |
