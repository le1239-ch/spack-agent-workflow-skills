# 阶段 1 AI 指令 (AI_INSTRUCTION.md)

> 本文件是给 AI Agent 的可直接执行指令。Agent 读取此文件后，按步骤执行即可完成阶段1。

---

## 指令

你是鲲鹏920F HPC 软件栈部署工作流的阶段1执行 Agent。你的任务是完成环境初始化：安装 Spack、配置鲲鹏 spack 仓库、安装 HPCKit、注册编译器。

> ⛔ **禁止自行修改任何 .md 文件**（如 env_report.md、DESCRIPTION.md 等）。如需修改，必须先向用户说明并获同意。脚本自动生成的 .md 不受此限。
> 🔒 **禁止修改指令文件**：AI_INSTRUCTION.md 和 DESCRIPTION.md 是工作流的固定指令定义，无论执行成功或失败，都不得以任何理由修改、追加、删除其内容。每次工作流执行完毕后，指令文件必须与执行前完全一致。

### 前置条件

- 当前机器为 aarch64 架构（鲲鹏920）
- 有 root 或 sudo 权限
- 网络可访问 github.com 和 gitcode.com

### 执行方式

直接运行脚本：

```bash
cd /home/zhangyuhang/workflow/stage1-setup-spack
bash setup_spack.sh
```

脚本会自动完成全部 10 个步骤。如果脚本执行失败，按下面的手动步骤逐一排查。

### 手动步骤（脚本失败时逐步排查）

#### 步骤 1：确认架构

```bash
uname -m
```
- 期望输出：`aarch64`
- 如果不是 aarch64，停止并报告错误

#### 步骤 2：安装 Spack（无条件安装到 workflow/spack-workflow/）

```bash
# 无条件下载独立实例，不借用系统已有的 spack
mkdir -p /home/zhangyuhang/workflow/spack-workflow
cd /home/zhangyuhang/workflow/spack-workflow
curl -L -o spack-1.2.1.tar.gz \
    https://github.com/spack/spack/releases/download/v1.2.1/spack-1.2.1.tar.gz
tar -xzf spack-1.2.1.tar.gz
source /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/share/spack/setup-env.sh
spack --version    # 验证
```

- 工作流始终使用 `workflow/spack-workflow/spack-1.2.1` 作为独立 spack 实例
- **不要**复用系统 PATH 中已有的 spack，即使 `command -v spack` 返回成功
- 记录 `SPACK_DIR`（`workflow/spack-workflow/spack-1.2.1`）和 `SPACK_ETC`（`$SPACK_DIR/etc/spack`）

#### 步骤 3：克隆鲲鹏 spack 仓库

```bash
git clone --depth 1 -b kunpeng920prof https://gitcode.com/wmrd/kp-spack.git \
    /home/zhangyuhang/workflow/spack-workflow/kp-spack-repo

# 验证
ls /home/zhangyuhang/workflow/spack-workflow/kp-spack-repo/kunpeng920prof/spack_repo/kunpeng920prof/repo.yaml
ls /home/zhangyuhang/workflow/spack-workflow/kp-spack-repo/kunpeng920prof/spack_repo/kunpeng920prof/packages/
```

- 期望看到 `repo.yaml` 文件和 `packages/` 目录（含 hpckit/hmpi/kpkml 等子目录）
- 如果克隆失败，检查网络，或尝试 `git clone https://gitcode.com/wmrd/kp-spack.git` 后 `git checkout kunpeng920prof`

#### 步骤 4：配置 Spack 配置文件

将以下三个文件写入 `$SPACK_ETC/`（即 `spack-1.2.1/etc/spack/`）：

> **scope 说明（重要）**：spack v1.x 的 scope→目录映射是 `user`=`$SPACK_USER_CONFIG_PATH`
> （本工作流已隔离到 `spack-workflow/user-config`）、`site`=`$SPACK_DIR/etc/spack/site`，
> 而 `$SPACK_DIR/etc/spack` 是工作流自己写配置的地方。所以**不要**用
> `spack config --scope=site get <section>` 导配置（那只读到 site 增量文件，是空壳）。
> 手动执行 spack 命令请先 `source /home/zhangyuhang/workflow/scripts/spack-env.sh`（独立 spack + 隔离 user scope）。

**repos.yaml**（鲲鹏 repo；builtin 由 spack 自身提供）：
```yaml
repos:
  - /home/zhangyuhang/workflow/spack-workflow/kp-spack-repo/kunpeng920prof/spack_repo/kunpeng920prof
```

**packages.yaml**：
```yaml
packages:
  all:
    target: [aarch64]
    providers:
      blas: [kpblas]
      lapack: [kplapack]
      mpi: [hmpi]
  hpckit:
    require: "@26.0.RC1"
  fftw:
    variants: +openmp +shared
  gromacs:
    variants: +mpi ~cuda build_type=Release
```

**config.yaml**：
```yaml
config:
  install_tree:
    root: $spack/opt/spack
  build_jobs: 32
  build_stage:
    - $spack/var/spack-stage
  install_hash_length: 7
  source_cache: $spack/var/cache
  dirty: false
  verify_ssl: true
```

#### 步骤 5：验证鲲鹏 repo 包可见性

```bash
spack repo list
# 期望看到 kunpeng920prof 在 builtin 之上

# 验证全部14个鲲鹏优化包 + hpckit 可见
for pkg in hpckit hmpi kpkml kpblas kplapack kpfft kpfftw \
           kpspblas kpscalapack kpscasolver kpsolver \
           kpvml kpksvml kpkupl; do
    spack info $pkg && echo "  ✅ ${pkg}" || echo "  ❌ ${pkg}"
done
```

- 如果 `spack info hpckit` 失败 → 检查 repos.yaml 路径是否正确
- 14个包全部 ✅ 才算通过

#### 步骤 6：安装 HPCKit

```bash
spack install hpckit@26.0.RC1

spack find -l hpckit
# 记录 hash 和安装路径
```

- HPCKit 包含：GCC 12.3.1、BiSheng 编译器、HMPI（鲲鹏优化 OpenMPI）、KML（鲲鹏数学库）
- 安装路径：`spack location -i hpckit`
- 安装后目录结构：`<prefix>/HPCKit/<版本>/compiler/{gcc,bisheng}/`

#### 步骤 7：注册编译器

```bash
HPCKIT_PREFIX=$(spack location -i hpckit)

# 找到 gcc 和 bisheng 的 bin 目录
GCC_BIN=$(find ${HPCKIT_PREFIX} -path "*/compiler/gcc/bin/gcc" | head -1)
BISHENG_BIN=$(find ${HPCKIT_PREFIX} -path "*/compiler/bisheng/bin/clang" | head -1)

# 注册到 spack（--scope=user：编译器 external 落在工作流隔离的 user-config/packages.yaml）
spack compiler find --scope=user $(dirname $GCC_BIN)
spack compiler find --scope=user $(dirname $BISHENG_BIN)

# 验证
spack compiler list
# 期望看到 gcc@12.3.1 和 llvm@19.1.7（bisheng 在 spack 中注册名为 llvm）
```

#### 步骤 8：验证 spec 解析

```bash
spack spec zlib       # 基础包
spack spec kpkml      # KML 元包
spack spec hmpi       # 鲲鹏 MPI
spack spec hpckit     # HPCKit 本体
```

- 全部成功 → 阶段1完成
- 任一失败 → 检查 packages.yaml 语法和 repos.yaml 路径

#### 步骤 9：产出报告

确认 `env_report.md` 已生成，包含以下通过条件全部 ✅：

| 条件 | 验证命令 |
|------|----------|
| target=aarch64 | `uname -m` |
| Spack 可用 | `spack --version` |
| kp-spack repo 已挂载 | `spack info hpckit` |
| HPCKit 已安装 | `spack find hpckit` |
| 编译器已注册 | `spack compiler list \| grep -E 'gcc\|bisheng\|clang\|llvm'` |
| spec 解析成功 | `spack spec zlib && spack spec kpkml` |

### 失败处理规则

1. **spack 下载失败**：检查网络；可手动下载 spack-1.2.1.tar.gz 放到 `workflow/spack-workflow/`
2. **kp-spack 克隆失败**：检查 gitcode 网络连接；可尝试 HTTPS 或 SSH 方式
3. **hpckit 安装失败**：检查华为镜像源连通性（hpckit 已在 packages.yaml 锁定 @26.0.RC1，不再回退旧版本）
4. **编译器注册失败**：手动执行 `spack compiler find --scope=user <bin目录>`（编译器 external 须落在工作流隔离的 user-config）
5. **spec 解析失败**：`spack config blame packages` 检查配置；`spack config validate packages` 验证语法

### 完成标志

当以下全部满足时，阶段1完成：

```bash
[ "$(uname -m)" = "aarch64" ]                                    # ✅ 架构
spack --version >/dev/null 2>&1                                   # ✅ Spack
spack info hpckit >/dev/null 2>&1                                 # ✅ repo
spack find hpckit >/dev/null 2>&1                                 # ✅ hpckit
spack compiler list 2>/dev/null | grep -qiE 'gcc@1[0-9]|bisheng|llvm' # ✅ 编译器
spack spec zlib >/dev/null 2>&1                                   # ✅ spec
spack spec kpkml >/dev/null 2>&1                                  # ✅ spec
```

全部 ✅ 后，将 `env_report.md` 路径告知调度器，进入阶段2。
