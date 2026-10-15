#!/bin/bash
#===============================================================================
# 阶段 1：环境盘点 + Spack 安装 + 鲲鹏 repo 配置 + HPCKit 安装 + 编译器注册
#
# 合并原阶段0和阶段1为一个完整脚本。流程：
#   1. 探测硬件/OS/NUMA（只读）
#   2. 确保 Spack 可用（无则下载 spack-1.2.1 到 workflow/spack-workflow/ 并解压；有则直接启用）
#   3. 克隆鲲鹏 spack 仓库（kp-spack, kunpeng920prof 分支）
#   4. 配置 config.yaml / repos.yaml / packages.yaml（鲲鹏 repo 优先于 builtin）
#   5. 安装 HPCKit（spack install hpckit@26.0.RC1）
#   6. 注册 HPCKit 中的 gcc + bisheng 编译器到 spack
#   7. 补充 packages.yaml variant 约束
#   8. 验证 spec 解析（zlib/kpkml/hmpi/hpckit）
#   9. 产出 env_report.md
#
# 用法：bash setup_spack.sh
# 通过条件：spack 可用、kp-spack repo 挂载、hpckit 安装、编译器注册、spec 解析成功
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib_common.sh"

REPORT="${SCRIPT_DIR}/env_report.md"

log_step "=== 阶段 1：环境盘点 + Spack 安装 + 鲲鹏 repo 配置 + 编译器注册 ==="

# ── 初始化报告 ────────────────────────────────────────────────────────────────
cat > "$REPORT" << 'HEADER'
# 环境基线报告 (env_report.md)

> 本文件由 setup_spack.sh 自动生成，请勿手动编辑。
> 后续所有阶段引用此文件中的路径和版本信息。

HEADER

echo "| 项目 | 值 |" >> "$REPORT"
echo "|------|-----|" >> "$REPORT"

# ── 1. 架构与 CPU（只读探测）────────────────────────────────────────────────
log_step "1. 确认架构与 CPU"

ARCH=$(uname -m)
echo "| 架构 | ${ARCH} |" >> "$REPORT"

if [ "$ARCH" != "aarch64" ]; then
    log_error "当前架构为 ${ARCH}，本工作流仅支持 aarch64！"
    echo ""
    echo "**⚠ 警告：架构不匹配，工作流可能无法正常运行**" >> "$REPORT"
else
    log_info "架构校验通过: aarch64"
fi

CPU_MODEL=$(lscpu | grep "Model name" | awk -F: '{print $2}' | xargs 2>/dev/null || echo "unknown")
CPU_CORES=$(nproc 2>/dev/null || echo "unknown")
NUMA_NODES=$(lscpu | grep "NUMA node(s)" | awk -F: '{print $2}' | xargs 2>/dev/null || echo "unknown")
SOCKETS=$(lscpu | grep "Socket(s)" | awk -F: '{print $2}' | xargs 2>/dev/null || echo "unknown")

echo "| CPU 型号 | ${CPU_MODEL} |" >> "$REPORT"
echo "| 总核数 | ${CPU_CORES} |" >> "$REPORT"
echo "| NUMA 节点数 | ${NUMA_NODES} |" >> "$REPORT"
echo "| Socket 数 | ${SOCKETS} |" >> "$REPORT"

{
    echo ""
    echo "## CPU 详细信息"
    echo ""
    echo '```'
    lscpu | head -30
    echo '```'
} >> "$REPORT"

# ── 2. 操作系统（只读探测）──────────────────────────────────────────────────
log_step "2. 确认操作系统"

OS_PRETTY=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | awk -F= '{print $2}' | tr -d '"' || echo "unknown")
echo "| 操作系统 | ${OS_PRETTY} |" >> "$REPORT"

{
    echo ""
    echo "## OS 详细信息"
    echo ""
    echo '```'
    cat /etc/os-release 2>/dev/null || echo "os-release 不可用"
    echo '```'
} >> "$REPORT"

# ── 3. 确保 Spack 可用（无条件安装到 workflow/spack-workflow/）──────────────
log_step "3. 确保 Spack 可用"

SPACK_INSTALLED_BY_WORKFLOW="false"
# 无条件在 workflow/spack-workflow/ 下安装独立 spack 实例，不借用系统已有的 spack
if [ -f "${SPACK_DIR}/bin/spack" ]; then
    log_info "工作流 Spack 已安装在 ${SPACK_DIR}，直接启用"
    source "${SPACK_DIR}/share/spack/setup-env.sh"
else
    log_info "工作流 Spack 未找到，开始自动安装到 ${SPACK_DIR}..."
    SPACK_INSTALLED_BY_WORKFLOW="true"
    ensure_spack || {
        log_error "Spack 安装失败，工作流无法继续"
        echo "| Spack 版本 | ❌ 安装失败 |" >> "$REPORT"
        exit 1
    }
fi

SPACK_VER=$(spack --version 2>/dev/null || echo "unknown")
SPACK_ARCH=$(spack arch 2>/dev/null || echo "unknown")
echo "| Spack 版本 | ${SPACK_VER} |" >> "$REPORT"
echo "| Spack 架构 | ${SPACK_ARCH} |" >> "$REPORT"
echo "| Spack 安装路径 | ${SPACK_DIR} |" >> "$REPORT"
echo "| Spack 配置目录 | ${SPACK_ETC} |" >> "$REPORT"
echo "| 由工作流安装 | ${SPACK_INSTALLED_BY_WORKFLOW} |" >> "$REPORT"

{
    echo ""
    echo "## Spack 已加载包"
    echo ""
    echo '```'
    spack find --loaded 2>/dev/null || echo "无已加载包"
    echo '```'
} >> "$REPORT"

# ── 4. 克隆鲲鹏 spack 仓库（kp-spack）──────────────────────────────────────
log_step "4. 配置鲲鹏 spack 仓库 (kp-spack)"

clone_kp_spack_repo || {
    log_error "kp-spack 仓库克隆失败"
    echo "| kp-spack repo | ❌ 克隆失败 |" >> "$REPORT"
}

KP_REPO_PATH=$(get_kp_repo_path)
echo "| kp-spack repo 路径 | ${KP_REPO_PATH} |" >> "$REPORT"

{
    echo ""
    echo "## 鲲鹏 repo 中的可用包"
    echo ""
    echo '```'
    ls "${KP_REPO_PATH}/packages/" 2>/dev/null || echo "无法列出"
    echo '```'
} >> "$REPORT"

# ── 5. 配置 config.yaml / repos.yaml / packages.yaml ──────────────────────
log_step "5. 配置 Spack 配置文件（鲲鹏 repo 优先于 builtin）"

# config.yaml
configure_config_yaml

# repos.yaml（鲲鹏 repo 优先于 builtin；本地 repo 由 stage3 创建后自行注册）
configure_repos_yaml

# packages.yaml（BLAS/LAPACK→kpkml, 编译器偏好, providers 指向 hmpi）
configure_packages_yaml

# 验证鲲鹏 repo 包可见性（全部14个包 + hpckit）
log_info "验证鲲鹏 repo 包可见性（14个鲲鹏数学库及优化组件 + hpckit）:"
KP_PKGS="hpckit hmpi kpkml kpblas kplapack kpfft kpfftw kpspblas kpscalapack kpscasolver kpsolver kpvml kpksvml kpkupl"
for pkg in $KP_PKGS; do
    if spack info "$pkg" &>/dev/null 2>&1; then
        echo "  ✅ ${pkg}"
    else
        echo "  ❌ ${pkg}"
    fi
done
echo "| 鲲鹏 repo 挂载验证 | $(spack info hpckit &>/dev/null 2>&1 && echo '✅ spack info hpckit 成功' || echo '❌ 失败') |" >> "$REPORT"

# ── 6. 安装 HPCKit ─────────────────────────────────────────────────────────
log_step "6. 安装 HPCKit（鲲鹏 HPC 开发套件）"

HPCKIT_STATUS="未安装"
if spack find hpckit &>/dev/null 2>&1; then
    log_info "hpckit 已安装，跳过"
    HPCKIT_STATUS="已安装"
else
    log_info "开始安装 hpckit@26.0.RC1..."
    if install_hpckit; then
        HPCKIT_STATUS="已安装"
        log_info "✅ HPCKit 安装成功"
    else
        HPCKIT_STATUS="❌ 安装失败"
        log_error "HPCKit 安装失败，后续编译器注册将受影响"
    fi
fi

HPCKIT_PREFIX=$(spack location -i hpckit 2>/dev/null || echo "")
echo "| HPCKit 状态 | ${HPCKIT_STATUS} |" >> "$REPORT"
echo "| HPCKit 安装路径 | ${HPCKIT_PREFIX:-未安装} |" >> "$REPORT"

# ── 7. 注册 HPCKit 编译器（gcc + bisheng）到 spack ────────────────────────
log_step "7. 注册 HPCKit 编译器（gcc + bisheng）"

if [ "$HPCKIT_STATUS" = "已安装" ]; then
    if register_hpckit_compilers; then
        # 实测断言：编译器（spack 1.x 里=external 包）必须落在工作流私有 user scope 里
        if grep -qE "externals:" "${SPACK_USER_CONFIG_PATH}/packages.yaml" 2>/dev/null \
           && spack compiler list 2>/dev/null | grep -qiE 'gcc@1[0-9]|clang|bisheng|llvm'; then
            echo "| 编译器注册 | ✅ gcc + bisheng 已注册（落盘 ${SPACK_USER_CONFIG_PATH}/packages.yaml） |" >> "$REPORT"
        else
            log_warn "编译器注册命令已执行，但未在工作流 user scope 找到编译器定义"
            echo "| 编译器注册 | ⚠ 未落盘到工作流 user scope（见 ${SPACK_USER_CONFIG_PATH}/） |" >> "$REPORT"
        fi
    else
        log_error "编译器注册失败（register_hpckit_compilers 返回非 0）"
        echo "| 编译器注册 | ❌ 注册失败 |" >> "$REPORT"
    fi
else
    echo "| 编译器注册 | ❌ hpckit 未安装，跳过 |" >> "$REPORT"
fi

# 探测 BiSheng 编译器路径（用于报告）
if find_bisheng 2>/dev/null; then
    BISHENG_VER=$("${BISHENG_BIN}" --version 2>/dev/null | head -1 || echo "unknown")
    echo "| BiSheng 路径 | ${BISHENG_DIR} |" >> "$REPORT"
    echo "| BiSheng 版本 | ${BISHENG_VER} |" >> "$REPORT"
else
    echo "| BiSheng 路径 | ⚠ 未找到 |" >> "$REPORT"
fi

# 加载 HPCKit 环境用于后续探测
if load_hpckit 2>/dev/null; then
    GCC_VER=$(gcc --version | head -1 2>/dev/null || echo "unknown")
    echo "| HPCKit 环境路径 | ${HPCKIT_BASE:-未找到} |" >> "$REPORT"
    echo "| GCC 版本 | ${GCC_VER} |" >> "$REPORT"
    if command -v mpicc &>/dev/null; then
        MPI_INFO=$(mpicc --showme 2>/dev/null | head -1 || echo "unknown")
        echo "| HMPI mpicc | ${MPI_INFO} |" >> "$REPORT"
    fi
fi

# ── 8. 补充 packages.yaml variant 约束 ────────────────────────────────────
log_step "8. 补充 packages.yaml variant 约束"

# 这些 variant 写入 $SPACK_ETC/site/packages.yaml（site scope 的增量文件）
if spack config --scope=site add "packages:fftw:variants:+openmp +shared" 2>&1; then
    log_info "✅ fftw variant 已写入 site scope"
else
    log_warn "❌ fftw variant 写入失败（详见上方 spack 输出）"
fi
# 注：不再写 openmpi variant —— 本工作流 MPI provider 是 hmpi，openmpi 属死配置
if spack config --scope=site add "packages:gromacs:variants:+mpi ~cuda build_type=Release" 2>&1; then
    log_info "✅ gromacs variant 已写入 site scope"
else
    log_warn "❌ gromacs variant 写入失败（详见上方 spack 输出）"
fi
log_info "packages.yaml variant 约束已补充（site scope: ${SPACK_ETC}/site/packages.yaml）"

# ── 9. 验证 spec 解析 ─────────────────────────────────────────────────────
log_step "9. 验证 spec 解析"

SPEC_OK=true

echo ""
echo "--- 验证: spack spec zlib ---"
if _spec_out=$(spack spec zlib 2>&1); then
    echo "$_spec_out" | head -20
    log_info "✅ zlib spec 解析成功"
else
    log_warn "zlib spec 解析失败"
    SPEC_OK=false
fi

echo ""
echo "--- 验证: spack spec kpkml ---"
if spack spec kpkml 2>&1 | head -30; then
    log_info "✅ kpkml spec 解析成功"
else
    log_warn "kpkml spec 解析失败"
    SPEC_OK=false
fi

echo ""
echo "--- 验证: spack spec hmpi ---"
if spack spec hmpi 2>&1 | head -30; then
    log_info "✅ hmpi spec 解析成功"
else
    log_warn "hmpi spec 解析失败"
    SPEC_OK=false
fi

echo ""
echo "--- 验证: spack spec hpckit ---"
if spack spec hpckit 2>&1 | head -30; then
    log_info "✅ hpckit spec 解析成功"
else
    log_warn "hpckit spec 解析失败"
    SPEC_OK=false
fi

echo "| spec 解析验证 | $($SPEC_OK && echo '✅ 全部成功' || echo '⚠ 部分失败') |" >> "$REPORT"

# ── 10. NUMA 拓扑 + kqmalloc + 配置来源 ─────────────────────────────────────
log_step "10. 记录 NUMA 拓扑 / kqmalloc / 配置来源"

record_numa "$REPORT"

KQMALLOC=""
for p in /usr/local/ksl/lib/libkqmalloc.so /usr/lib64/libkqmalloc.so; do
    if [ -f "$p" ]; then
        KQMALLOC="$p"
        break
    fi
done
echo "| kqmalloc | ${KQMALLOC:-⚠ 未找到} |" >> "$REPORT"

{
    echo ""
    echo "## Spack 配置来源"
    echo ""
    echo '```'
    spack config list 2>/dev/null || echo "config list 不可用"
    echo '```'
    echo ""
    echo "## 当前 repos.yaml"
    echo ""
    echo '```'
    cat "${SPACK_ETC}/repos.yaml" 2>/dev/null || echo "repos.yaml 不存在"
    echo '```'
    echo ""
    echo "## 当前 packages.yaml"
    echo ""
    echo '```'
    cat "${SPACK_ETC}/packages.yaml" 2>/dev/null || echo "packages.yaml 不存在"
    echo '```'
} >> "$REPORT"

# ── 导出配置文件副本到本目录 ──────────────────────────────────────────────────
# ⚠ 不要用 `spack config --scope=site get <section>`：site scope 是 $SPACK_DIR/etc/spack/site，
#   而工作流的配置写在 $SPACK_ETC（etc/spack）。照旧写法导出的是空壳
#   （compilers: [] / repos: {} / 只有 variant 片段的 packages.yaml）。
log_step "导出配置文件副本（真实生效的配置）"

for _sec in config compilers packages repos; do
    if [ -f "${SPACK_ETC}/${_sec}.yaml" ]; then
        cp -f "${SPACK_ETC}/${_sec}.yaml" "${SCRIPT_DIR}/${_sec}.yaml"
    else
        echo "# ${_sec}.yaml 不在 ${SPACK_ETC}/ —— 本工作流未生成该文件" > "${SCRIPT_DIR}/${_sec}.yaml"
    fi
done

# 编译器 externals 落在工作流 user scope，单独导出留证
if [ -f "${SPACK_USER_CONFIG_PATH}/packages.yaml" ]; then
    { echo "# 说明：工作流私有 user scope 的 packages.yaml（spack 1.x 编译器 externals 在此）"
      cat "${SPACK_USER_CONFIG_PATH}/packages.yaml"; } > "${SCRIPT_DIR}/packages.user-scope.yaml"
fi
log_info "配置文件已导出到 ${SCRIPT_DIR}/（另含 packages.user-scope.yaml）"

# ── 通过条件检查 ──────────────────────────────────────────────────────────────
{
    echo ""
    echo "## 通过条件检查"
    echo ""
    echo "| 条件 | 状态 |"
    echo "|------|------|"
    echo "| target=aarch64 | $([ "$ARCH" = "aarch64" ] && echo '✅' || echo '❌') |"
    echo "| Spack 可用 | $([ -n "${SPACK_VER:-}" ] && [ "$SPACK_VER" != "unknown" ] && echo '✅' || echo '❌') |"
    echo "| kp-spack repo 已挂载 | $([ -f "${KP_REPO_PATH}/repo.yaml" ] && echo '✅' || echo '❌') |"
    echo "| spack info hpckit 成功 | $(spack info hpckit &>/dev/null 2>&1 && echo '✅' || echo '❌') |"
    echo "| HPCKit 已安装 | $([ "$HPCKIT_STATUS" = "已安装" ] && echo '✅' || echo '❌') |"
    echo "| 编译器已注册 | $(spack compiler list 2>/dev/null | grep -qiE 'gcc@1[0-9]|bisheng|clang|llvm' && echo '✅' || echo '❌') |"
    echo "| spec 解析成功 | $($SPEC_OK && echo '✅' || echo '⚠') |"
} >> "$REPORT"

log_info "环境报告已生成: $REPORT"
log_step "=== 阶段 1 完成 ==="
