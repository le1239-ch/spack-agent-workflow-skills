# 阶段 1：环境盘点 + Spack 安装 + 鲲鹏 repo 配置 + HPCKit 安装 + 编译器注册

## 目标

完成环境探测、Spack 安装、鲲鹏 spack repo 挂载、HPCKit 安装、编译器注册、配置验证。
一个脚本完成全部初始化工作，产出 `env_report.md` 供后续阶段引用。

## 输入

无（首次运行，从零开始）

## 动作清单（10 步）

### 步骤 1 — 探测硬件/OS/NUMA（只读）
```bash
uname -m && lscpu | head -30
cat /etc/os-release
numactl -H
```

### 步骤 2 — 确保 Spack 可用
```bash
# 工作流必定使用自己的独立实例：即使 command -v spack 成功也不借用系统 spack
mkdir -p /home/zhangyuhang/workflow/spack-workflow && cd /home/zhangyuhang/workflow/spack-workflow
# 已安装则跳过下载（ensure_spack 幂等）
curl -L -o spack-1.2.1.tar.gz \
    https://github.com/spack/spack/releases/download/v1.2.1/spack-1.2.1.tar.gz
tar -xzf spack-1.2.1.tar.gz
source /home/zhangyuhang/workflow/spack-workflow/spack-1.2.1/share/spack/setup-env.sh
```

### 步骤 3 — 克隆鲲鹏 spack 仓库（kp-spack）
```bash
git clone --depth 1 -b kunpeng920prof https://gitcode.com/wmrd/kp-spack.git \
    /home/zhangyuhang/workflow/spack-workflow/kp-spack-repo

# 仓库含: hpckit/hmpi/kpkml/kpblas/kplapack/kpfft/kpfftw/kpscalapack/
#         kpksvml/kpvml/kpkupl/lammps_opt/py_numpy 等 19 个包
```

### 步骤 4 — 配置 config.yaml / repos.yaml / packages.yaml
```bash
# 配置文件放在 spack-1.2.1/etc/spack/ 下

# repos.yaml — 鲲鹏 repo 优先于 builtin
# 注意：本地 repo（自写 package.py）由 stage3 调用 create_local_repo 后自动注册
cat > etc/spack/repos.yaml << 'EOF'
repos:
  - /home/zhangyuhang/workflow/spack-workflow/kp-spack-repo/kunpeng920prof/spack_repo/kunpeng920prof
EOF

# packages.yaml — BLAS/LAPACK provider→kpblas/kplapack, MPI→hmpi, hpckit 锁 @26.0.RC1
cat > etc/spack/packages.yaml << 'EOF'
packages:
  all:
    target: [aarch64]
    providers:
      blas: [kpblas]
      lapack: [kplapack]
      mpi: [hmpi]
  hpckit:
    require: "@26.0.RC1"
EOF

# config.yaml — 安装树/构建/缓存等基本配置
cat > etc/spack/config.yaml << 'EOF'
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
EOF
```

### 步骤 5 — 验证鲲鹏 repo 包可见性
```bash
spack repo list | grep kunpeng920prof
# 验证全部14个鲲鹏优化包 + hpckit 可见
for pkg in hpckit hmpi kpkml kpblas kplapack kpfft kpfftw \
           kpspblas kpscalapack kpscasolver kpsolver \
           kpvml kpksvml kpkupl; do
    spack info $pkg && echo "  ✅ ${pkg}" || echo "  ❌ ${pkg}"
done
```

### 步骤 6 — 安装 HPCKit
```bash
spack install hpckit@26.0.RC1
spack find -l hpckit
```

### 步骤 7 — 注册 HPCKit 中的 gcc + bisheng 编译器到 spack
```bash
HPCKIT_PREFIX=$(spack location -i hpckit)
spack compiler find --scope=user ${HPCKIT_PREFIX}/HPCKit/*/compiler/gcc/bin
spack compiler find --scope=user ${HPCKIT_PREFIX}/HPCKit/*/compiler/bisheng/bin
spack compiler list
```

### 步骤 8 — 补充 packages.yaml variant 约束
```bash
spack config --scope=site add "packages:fftw:variants:+openmp +shared"
spack config --scope=site add "packages:gromacs:variants:+mpi ~cuda build_type=Release"
```

### 步骤 9 — 验证 spec 解析
```bash
spack spec zlib       # 基础包 spec
spack spec kpkml      # KML 元包 spec
spack spec hmpi       # MPI spec
spack spec hpckit     # HPCKit spec
```

### 步骤 10 — 产出 env_report.md + 导出配置文件副本

## 脚本

`setup_spack.sh` — 自动执行上述全部 10 步。核心函数来自 `scripts/lib_common.sh`：
- `ensure_spack()` — 检查并自动安装 spack
- `clone_kp_spack_repo()` — 克隆 kp-spack 仓库
- `configure_config_yaml()` / `configure_repos_yaml()` / `configure_packages_yaml()` — 写配置文件
- `install_hpckit()` — 安装 HPCKit
- `register_hpckit_compilers()` — 注册 gcc + bisheng 编译器

## 输出

| 文件 | 说明 |
|------|------|
| `env_report.md` | 环境报告（路径/版本/NUMA/配置/通过条件检查） |
| `packages.yaml` | `$SPACK_ETC/packages.yaml` 的真实副本（BLAS provider→kpblas / LAPACK provider→kplapack，含全部鲲鹏库 compiler_variant 声明） |
| `packages.user-scope.yaml` | 工作流私有 user scope 的 packages.yaml —— **编译器 externals（gcc/bisheng）实际在这里** |
| `compilers.yaml` | `$SPACK_ETC/compilers.yaml`（spack 1.x 编译器以 external 包记录，通常只在上面的 user-scope 文件里） |
| `repos.yaml` | `$SPACK_ETC/repos.yaml`（鲲鹏 repo；builtin 由 spack 自身提供，不写死路径） |

## 通过条件

- [ ] `target=aarch64` 确认
- [ ] Spack 可用（`spack --version` 成功）
- [ ] kp-spack repo 已挂载（`spack info hpckit` 成功）
- [ ] HPCKit 已安装（`spack find hpckit` 成功）
- [ ] 编译器已注册（`spack compiler list` 含 gcc + bisheng/clang）
- [ ] spec 解析成功（`spack spec zlib` / `spack spec kpkml`）

## 失败处理

- **spack 下载失败** → 检查网络，可手动下载 tarball 放到 `workflow/spack-workflow/`
- **kp-spack 克隆失败** → 检查 gitcode 网络连接，可手动 `git clone`
- **hpckit 安装失败** → 检查华为镜像源连通性（hpckit 已在 packages.yaml 锁定 @26.0.RC1，不再回退旧版本）
- **编译器注册失败** → 手动 `spack compiler find` 指定路径
- **spec 解析失败** → 检查 packages.yaml 语法，`spack config blame packages`

## Agent 契约

| 项目 | 值 |
|------|-----|
| 允许动作 | 只读探测 + curl 下载 spack + git clone kp-spack + spack install hpckit + spack compiler find + 写配置文件 |
| 禁止动作 | 安装 HPC 应用包（阶段3才装）、改官方 recipe |
| 输入 | 无 |
| 输出 | `env_report.md` + `packages.yaml` / `compilers.yaml` / `repos.yaml` |
| 超时 | 30 分钟（hpckit 安装可能较慢） |
