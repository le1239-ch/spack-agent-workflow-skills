# Spack 安装阶段常见问题速查

> 阶段3（批量安装 HPC 软件栈）中遇到的 spack 安装/concretizer 问题与修复。

## 1. BiSheng 编译器在 spack 中注册为 `llvm`，不是 `bisheng`

**现象：** `spack install gromacs %bisheng` 报错 `'gromacs@2026.1 %bisheng' cannot depend on bisheng`。

**根因：** BiSheng 编译器在 spack `compiler list` 中注册为 `llvm`（如 `llvm@17.0.6`、`llvm@19.1.7`），HPCKit 的 BiSheng 编译器以 clang/flang 二进制形式注册在外部 `llvm` 包中。

**修复：** 用 `%llvm` 指定 BiSheng 编译器：
```bash
# 错
spack install gromacs@2026.1 %bisheng
# 对
spack install gromacs@2026.1 %llvm
```

**验证：** `spack compiler list` 输出 `llvm@<version>` 条目，`spack compiler info llvm@<version>` 的 prefix 指向 HPCKit 的 bisheng 目录。

**批量安装脚本实测（2026-09，workflow install_batch.sh）：** 脚本对清单 `bisheng`/`both` 条目在**多处**硬拼 `%bisheng` 构造 spec，`spack spec` 预校验即报 `cannot depend on bisheng`；其"spec 解析失败→简化重拼"的兜底逻辑重新拼出的还是同一个 `%bisheng` spec，重试全部无效，最终在 install_log 留下 ❌ spec失败 记录。修复应在脚本拼接处统一加 bisheng→llvm 映射（注意覆盖所有拼接点），或清单只填 `gcc`。

## 2. local_repo openblas 遮蔽 builtin openblas 导致 `No such variant 'threads'`

**现象：** 所有依赖 blas 的包（gromacs/lammps/openfoam/quantum-espresso/cp2k/elmerfem）spec 解析全部失败：
```
==> Error: No such variant 'threads' in package openblas
```

**根因：** local_repo（用户自定义仓库）中有一个简化版 `openblas` package.py，只有 `build_system` variant + `depends_on("llvm")`，缺少 builtin openblas 的 `threads`（pthreads/openmp/none）variant。由于 local_repo 在 repos.yaml 中排在 builtin 之前，local_repo 的 openblas **遮蔽**（shadow）了 builtin。

cp2k 的 package.py 有 `depends_on("openblas threads=openmp", when="^[virtuals=blas] openblas")`，当 concretizer 评估 openblas 作为 blas provider 候选时，尝试设置 `threads=openmp` variant，但 local_repo openblas 没有这个 variant → 报错。

**修复方式（推荐）：** 重命名或移除 local_repo 中的 openblas，让 builtin 恢复可见：
```bash
mv /path/to/local_repo/packages/openblas /path/to/local_repo/packages/openblas.bak
# 或直接删除
rm -rf /path/to/local_repo/packages/openblas
```

**为什么不用 `buildable: false`？** 在 packages.yaml 中设 `openblas: {buildable: false}` 不够 — concretizer 仍会验证 openblas 的 variant 有效性，即使不构建它。

**为什么不用 `blas: [kpkml]` 排除 openblas？** spack 的 provider 列表是**跨 scope 合并**的，不是替换。系统级 `blas: [kpkml]` + 默认 `blas: [openblas]` = 合并后 `blas: [kpkml, openblas]`。要完全移除需编辑 `defaults/base/packages.yaml`，但这会修改 spack 内部文件。

**最佳实践：** local_repo 中不要放置与 builtin 同名的简化包。如果需要自定义 openblas，应给它取不同的包名。

## 3. spack provider 列表跨 scope 合并

**现象：** 系统级 `packages.yaml` 已设 `blas: [kpkml]`，但合并配置仍显示 `blas: [kpkml, openblas]`。

**根因：** spack 的 `packages:all:providers` 列表是**追加合并**的，不是替换。每个 scope（defaults → system → user）的 provider 列表会被拼接。

**验证：**
```bash
spack config blame packages | grep "blas:"
# 显示各 scope 的贡献
```

**影响：** 即使在 user scope 设 `blas: [kpkml]`，defaults 中的 `blas: [openblas]` 仍会加入候选列表。如果 openblas 有 variant 问题（见上条），即使 kpkml 排在第一位也会导致整体失败。

## 4. Spack 1.2.1 本地仓库注册需要 `spack_repo/<namespace>/` 结构

**现象：** `spack repo add /path/to/my-repo` 报错 `Path must contain 'spack_repo/'`。

**根因：** Spack 1.2.1 要求仓库目录下有 `spack_repo/<namespace>/` 子目录结构，repo.yaml 放在 `<namespace>/` 目录内。

**正确结构：**
```
my-repo/                           # 仓库根（注册路径）
└── spack_repo/
    └── my_workflow/               # namespace 目录
        ├── repo.yaml               # namespace 声明
        └── packages/              # 包目录
            └── my_pkg/
                └── package.py
```

**注册方式：**
```bash
# 方式 1：spack repo add（可能因结构校验失败）
spack repo add /path/to/my-repo

# 方式 2：直接写 config（更可靠）
spack config add "repos:my_workflow:/path/to/my-repo/spack_repo/my_workflow"
```

**注意：** repo.yaml 内容：
```yaml
repo:
  namespace: 'my_workflow'
  api: v2.4
```

**⚠ namespace 必须全小写（实测 2026-09）：** 脚本从 CPU 型号派生的 namespace `kunpeng920F_workflow` 含大写字母，spack 判为非法仓库：
```
==> Warning: Error constructing repository '.../kunpeng920F_workflow':
    Invalid namespace 'kunpeng920F_workflow' in repo '...'
```
`spack repo list` 显示 `[-]` 状态，但每条 spack 命令只发警告、不失败。**坑在幂等注册检查**：脚本用 `spack repo list | grep -q "<路径>"` 判断"已注册则跳过"——坏 namespace 的条目也带路径，grep 命中即跳过 `repo add`，坏状态**永不自愈**。修复：repo.yaml 的 namespace 改成全小写（如 `kunpeng920f_workflow`）后重新注册（或 `spack repo remove` 旧条目再 add）。派生 namespace 的脚本应加 `tr '[:upper:]' '[:lower:]'`。

## 5. cp2k 不支持 BiSheng（%clang）编译器

**现象：** `spack install cp2k %llvm` 报错：
```
conflicts with '%clang'
```

**根因：** cp2k 的 package.py 中有 `conflicts("%clang")` 声明，明确不支持 clang/BiSheng 编译器。这是上游限制，无法绕过。

**影响：** 清单中标记 `both`（gcc+bisheng）的 cp2k 只能装 gcc 版本。

## 6. openblas 测试失败导致安装中断

**现象：** `spack install quantum-espresso@7.2 %gcc` 失败，openblas@0.3.33 的 6 个测试失败：
```
RESULTS: 1522 tests (1516 ok, 6 failed, 0 skipped)
make: *** [Makefile:90: run_test] Error 6
```

**根因：** openblas@0.3.33 在 aarch64（鲲鹏920）上的部分 BLAS 测试不通过，spack 默认运行 `--test root`（只测试根包的依赖），openblas 测试失败导致整个安装链中断。

**修复：** 用 `--no-checksum` 跳过验证（注意：这不是跳过测试的正确方式）。实际上应使用 `spack install --no-checksum` 或在 packages.yaml 中为 openblas 设 `verify: false`。

**注意：** `--no-check` 不是有效参数（ambiguous with `--no-check-signature` 和 `--no-checksum`）。

## 7. gromacs@2026.1 在 aarch64 上编译失败

**现象：** `hardwaretopology.cpp` 编译错误（gcc 和 bisheng 均失败）。

**建议：** 降级到 gromacs@2025.4 或 2024.6。

## 8. xrootd/protobuf 编译失败导致 openfoam 安装中断

**现象：** openfoam 的依赖 xrootd@5.9.2 和 protobuf@34.1 编译失败。

**建议：** 尝试 `openfoam ~cow` 禁用 xrootd 依赖，或降级 openfoam 版本。
