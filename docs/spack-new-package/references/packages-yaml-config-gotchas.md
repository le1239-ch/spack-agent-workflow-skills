# Spack packages.yaml 配置陷阱（鲲鹏 kp-spack 仓库场景）

> 本文件记录在配置鲲鹏 spack 仓库（kunpeng920prof repo）到已有 Spack 1.2.1 安装时遇到的 `packages.yaml` 语法与 concretization 冲突问题。

## 场景

已有 Spack 1.2.1 安装（含大量 externals：系统 gcc/llvm、cmake/python/zlib 等），需要挂载鲲鹏 kp-spack 仓库并配置 `packages.yaml` 指向 kpkml/hmpi/hpckit。

## 陷阱 1：多值变体 `require` 不能用 `+` 前缀

**错误写法**（AI_INSTRUCTION.md 原始模板中的写法）：
```yaml
kpkml:
  require: "+compiler_variant=gcc"
```

**报错**：
```
==> Error: unexpected characters in the spec string
+compiler_variant=gcc
                 ^
```

**原因**：`compiler_variant` 是 `variant(default="gcc", values=("gcc", "bisheng"), multi=False)` 定义的多值变体（非布尔型）。`+` 前缀仅适用于布尔变体（`+openmp` / `~cuda`）。多值变体在 spec 字符串中直接写 `variant_name=value`。

**正确写法**：
```yaml
kpkml:
  require: "compiler_variant=gcc"
```

同样适用于 `kplapack`、`kpblas`、`kpfft`、`kpfftw`、`hmpi` 等所有含 `compiler_variant` 变体的包。

## 陷阱 2：`all.compiler` 在 Spack v1.0+ 已废弃

**错误写法**：
```yaml
packages:
  all:
    compiler: [bisheng, gcc]
```

**警告**（不阻止执行但配置被忽略）：
```
==> Warning: The packages:all:compiler preference has been deprecated in Spack v1.0, and is currently ignored. It will be removed from config in Spack v1.2.
```

**原因**：Spack v1.0 起不再支持通过 `packages.yaml` 的 `all.compiler` 字段设置全局编译器偏好。编译器选择应通过 `compilers.yaml`（`spack compiler find` 自动生成）和安装时的 `%gcc` / `%llvm` spec 约束来控制。

**正确做法**：移除 `all.compiler` 行，仅在安装时通过 `%gcc` 或 `%llvm` 指定编译器。`packages.yaml` 的 `all:` 只保留 `target` 和 `providers`。

## 陷阱 3：强制 `hpckit@26.1.RC1` 会破坏 kpkml concretization

**错误写法**：
```yaml
hpckit:
  require: "@26.1.RC1"
```

**报错**（`spack spec kpkml` 失败）：
```
==> Error: failed to concretize `kpkml` for the following reasons:
     1. hpckit cannot come from both builtin and kunpeng920prof namespaces
     2. Cannot select a single "version" for package "hpckit"
     3. Cannot satisfy 'hpckit@26.1.RC1' (version 25.1.0 does not match)
        required because kpvml depends on hpckit@26.1.RC1 when @26.1.RC1
```

**根本原因**：版本依赖链冲突。
- `kpkml` 只有 `26.0.RC1` 和 `25.1.0` 两个版本（**没有 26.1.RC1**）
- `kpkml@26.0.RC1` → `depends_on("hpckit@26.0.RC1")`
- 但 `kpkml` 依赖子包 `kpblas`（无版本约束）→ concretizer 选最高版本 `26.1.RC1`
- `kpblas@26.1.RC1` → `depends_on("hpckit@26.1.RC1")`
- 现在需要 `hpckit@26.0.RC1` AND `hpckit@26.1.RC1` → 不可能同时满足
- `packages.yaml` 强制 `hpckit@26.1.RC1` 进一步加剧冲突

**正确做法**：**不要**在 `packages.yaml` 中对 `hpckit` 设置版本 `require`。让 concretizer 根据依赖链自行选择匹配版本。`kpkml` 会解析为 `kpkml@26.0.RC1` → `hpckit@26.0.RC1` + 所有子包 `@26.0.RC1`，版本一致无冲突。

```yaml
# 正确：不对 hpckit 设置版本约束
# hpckit 行完全省略，或只写注释说明
```

## 陷阱 4：hpckit 在 builtin 和 kunpeng920prof 双 repo 定义导致 namespace 冲突

**现象**：`spack spec kpkml` 报 `hpckit cannot come from both builtin and kunpeng920prof namespaces`。

**原因**：`hpckit` 包同时存在于：
1. kunpeng920prof repo（kp-spack 仓库）
2. builtin repo（spack-packages-2026.06.0 内置）

Spack concretizer 在解析 kpkml 依赖 hpckit 时，会同时考虑两个 repo 的 hpckit 定义，产生 namespace 冲突。

**缓解方式**：
- `repos.yaml` 中将 `kunpeng920prof` 放在 `builtin` 之上（优先级更高）
- 移除 `packages.yaml` 中的 `hpckit` 版本约束（消除版本冲突后 namespace 冲突通常也会消失）
- 如果仍冲突，可用 namespace 限定 spec：`spack spec 'kunpeng920prof.kpkml'`

**注意**：只有 `hpckit` 存在此问题——其他鲲鹏包（hmpi/kpkml/kpblas 等）只存在于 kunpeng920prof repo，builtin 中没有。

## 陷阱 5：配置合并策略——不能覆盖已有 externals

当 Spack 已有大量 externals 配置（外部编译器 llvm/gcc、系统包 automake/openssl/tar/python/zlib/cmake 等）时，**不能**用 `cat > packages.yaml` 直接覆盖整个文件。

**正确做法**：
1. 备份现有配置：`cp packages.yaml packages.yaml.bak.$(date +%Y%m%d_%H%M%S)`
2. 在 `packages:` 顶部添加鲲鹏优化段（`all:` target/providers、kp* require、fftw/gromacs variants）
3. 保留所有已有的 `externals:` 段（llvm/gcc 编译器、系统包）
4. 验证合并后配置：`spack config blame packages | head -20`

## 陷阱 6：`kpkml` 不是 blas/lapack provider —— 写 `providers: blas: [kpkml]` 无效，会静默回退 openblas

**现象**：`packages.yaml` 里按直觉写

```yaml
all:
  providers:
    blas: [kpkml]
    lapack: [kpkml]
```

配置看起来生效了（`spack config blame packages` 显示 `blas: [kpkml, openblas]`，kpkml 还排在第一位），但实际 concretize 出来的 BLAS **是 openblas，不是鲲鹏 KML**：

```
$ spack spec elmerfem@9.0 %gcc@12.3.1
 -   openblas@0.3.30 ... threads=none     <-- 期望是 kpblas/kpkml
 -   netlib-scalapack@2.2.2 ...
```

**根因**：provider 列表里只有**声明了 `provides()` 的包**才是有效候选。实测（`grep -nE "provides|class " <repo>/packages/*/package.py`）：

| 包 | provides | 说明 |
|----|----------|------|
| `kpkml` | **无** | 只是聚合/元包，`depends_on` kpblas/kpfft/kpksvml/kpvml/kplapack，自身不 `provides` 任何虚拟包 |
| `kpblas` | `blas` | ✅ 真正的 blas provider |
| `kplapack` | `lapack` | ✅ 真正的 lapack provider |
| `kpscalapack` | `scalapack` | ✅ 真正的 scalapack provider |
| `hmpi` | `mpi` | ✅ MPI 侧正常（所以 `mpi: [hmpi]` 有效，解析结果确实落到 hmpi） |

把不 `provides` 的包写进 provider 列表**不会报错、不会告警**，concretizer 直接忽略它，回退到下一个候选（builtin 的 `openblas`）。症状是"配置看起来对、日志干净、但装出来根本没链 KML"——**只能靠检查 concretize 结果发现**。

**正确写法**：

```yaml
all:
  providers:
    blas: [kpblas]          # 不要写 kpkml
    lapack: [kplapack]      # 不要写 kpkml
    scalapack: [kpscalapack]
    mpi: [hmpi]
```

若确实要让某个包整体用 KML，除了 provider 写对，还要在具体包的 spec 上加 `^kpkml`（或 `^kpblas`）显式约束。

**验证（必做）**：provider 配好后必须看 concretize 结果里**实际**出现的 blas 包，不能只看 `config blame`：

```bash
spack spec <pkg>@<ver> %gcc@12.3.1 | grep -iE "openblas|kpblas|kplapack|kpkml"
# 期望 kpblas/kplapack/kpkml；出现 openblas 即说明 provider 没生效
```

**注意**：builtin 的 `openblas` 永远在候选里（跨 scope 的 provider 列表是**追加合并**而非替换），所以只要 KML 包没被正确列为 provider，就必然静默落到 openblas。

## 正确的 packages.yaml 鲲鹏优化段模板

```yaml
packages:
  # ── 全局架构与 provider 偏好 ──
  all:
    target: [aarch64]
    providers:
      blas: [kpblas]        # 见陷阱 6：kpkml 不 provides(blas)，写 kpkml 会静默回退 openblas
      lapack: [kplapack]
      scalapack: [kpscalapack]
      mpi: [hmpi]
    # 注意：不要写 compiler: [bisheng, gcc]，Spack v1.0+ 已废弃

  # ── KML 鲲鹏数学库（多值变体，不用 + 前缀）──
  kpkml:
    require: "compiler_variant=gcc"
  kplapack:
    require: "compiler_variant=gcc"
  kpblas:
    require: "compiler_variant=gcc"
  kpfft:
    require: "compiler_variant=gcc"
  kpfftw:
    require: "compiler_variant=gcc"

  # ── HMPI ──
  hmpi:
    require: "compiler_variant=gcc"

  # ── HPCKit：不强制版本，让 concretizer 自行选择 ──
  # hpckit 行省略！强制 @26.1.RC1 会与 kpkml 子包版本依赖冲突

  # ── 其他包变体约束 ──
  fftw:
    variants: +openmp +shared
  gromacs:
    variants: +mpi ~cuda build_type=Release

  # ── 以下保留原有 externals（llvm/gcc/automake/openssl/...）──
```

## 验证命令

```bash
# 验证 spec 解析（全部应成功无报错）
spack spec zlib       # 基础包
spack spec kpkml      # KML 元包（验证版本链一致性）
spack spec hmpi       # 鲲鹏 MPI
spack spec hpckit     # HPCKit 本体

# 验证 provider 真的生效（关键！只 config blame 看不出问题，见陷阱 6）
spack config blame packages 2>&1 | grep -A6 "providers"     # 看 provider 列表来源
spack spec kpkml | grep -iE "openblas|kpblas|kplapack"      # 应出现 kpblas/kplapack
spack spec <待装包>@<版本> %gcc@12.3.1 | grep -iE "openblas|kpblas|kplapack|kpkml"
# 出现 openblas 即 provider 没生效

# 验证 repo 挂载
spack repo list       # kunpeng920prof 应在 builtin 之上
spack info hpckit     # 应输出包信息
spack info kpkml      # 应输出包信息
```
