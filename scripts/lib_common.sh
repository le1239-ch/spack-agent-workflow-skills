#!/bin/bash
#===============================================================================
# 公共函数库 — 所有阶段脚本 source 此文件
# 用途：统一日志格式、环境校验、Spack 自动安装、HPCKit 环境加载、spack 命令封装
#===============================================================================
set -euo pipefail

# ── 颜色与日志 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
export RED GREEN YELLOW BLUE NC

log_info()  { echo -e "${GREEN}[INFO]${NC}  $(date '+%H:%M:%S') | $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') | $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') | $*" >&2; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $(date '+%H:%M:%S') | $*"; }

# ── 工作流根目录 ──────────────────────────────────────────────────────────────
export WORKFLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── 产出文件路径 ──────────────────────────────────────────────────────────────
export ENV_REPORT="${WORKFLOW_ROOT}/stage1-setup-spack/env_report.md"
export INSTALL_LOG="${WORKFLOW_ROOT}/stage3-install/install_log.md"

# ── Spack 安装相关常量 ────────────────────────────────────────────────────────
# spack-workflow 放在 workflow 目录下（避免 ~ 目录空间不足）
export SPACK_WORKFLOW_DIR="${WORKFLOW_ROOT}/spack-workflow"
export SPACK_VERSION="1.2.1"
export SPACK_DIR="${SPACK_WORKFLOW_DIR}/spack-${SPACK_VERSION}"
export SPACK_ETC="${SPACK_DIR}/etc/spack"
# ── 工作流私有 user scope（隔离 /root/.spack 的跨项目污染）───────────────────
# 不隔离时：本地 root 用户的 /root/.spack 里还有其他项目的 repo（如别人的
# aitiaoyou_work、my_workflow，实测 191 个 *-opt 包会进入本工作流的解析视图），
# 还有同名 namespace；且编译器 externals（spack 1.x 编译器=external 包）只落在
# 工作流之外，换机器/换用户即失效。隔离后 user scope 全部落在 spack-workflow/ 内。
export SPACK_USER_CONFIG_PATH="${SPACK_WORKFLOW_DIR}/user-config"
export SPACK_USER_CACHE_PATH="${SPACK_WORKFLOW_DIR}/user-cache"

# 初始化工作流私有 user scope，并从旧的全局 user scope 迁移必要内容
init_workflow_user_scope() {
    mkdir -p "${SPACK_USER_CONFIG_PATH}" "${SPACK_USER_CACHE_PATH}"

    # 编译器 externals（gcc/bisheng）→ 迁移，否则 %gcc/%llvm 立刻失效
    # 注意：spack 在隔离后的空 user scope 里会自己生成一份 packages.yaml（只含系统
    # gcc/clang），此时不能因为「文件已存在」就跳过迁移，否则 HPCKit 编译器永远进不来
    local _uc_pkgs="${SPACK_USER_CONFIG_PATH}/packages.yaml"
    if [ -f /root/.spack/packages.yaml ] && grep -q "HPCKit" /root/.spack/packages.yaml; then
        if [ ! -f "$_uc_pkgs" ] || ! grep -q "HPCKit" "$_uc_pkgs"; then
            [ -f "$_uc_pkgs" ] && mv -f "$_uc_pkgs" "${_uc_pkgs}.auto-$(date +%Y%m%d-%H%M%S)"
            cp -f /root/.spack/packages.yaml "$_uc_pkgs"
            log_warn "已迁移 HPCKit 编译器 externals（/root/.spack/packages.yaml）→ 工作流 user scope"
        fi
    fi

    # 本地 repo 注册 → 只迁移本工作流自己的（*_workflow），丢掉其他项目的 repo
    if [ ! -f "${SPACK_USER_CONFIG_PATH}/repos.yaml" ]; then
        # ⚠ 过滤要锚定本机型号（kunpeng*_workflow）：只写 `_workflow:` 会把其他项目的
        #    my_workflow 一起带进来（实测带进 12 个外来 *-opt 包）
        if [ -f /root/.spack/repos.yaml ] && grep -qE '^[[:space:]]*kunpeng[0-9a-z]*_workflow:' /root/.spack/repos.yaml; then
            { echo "repos:"; grep -E '^[[:space:]]*kunpeng[0-9a-z]*_workflow:' /root/.spack/repos.yaml; } > "${SPACK_USER_CONFIG_PATH}/repos.yaml"
            log_warn "已在工作流 user scope 重建 repos.yaml（仅保留本工作流 kunpeng*_workflow 本地 repo，已剔除其他项目 repo）"
        else
            echo "repos: {}" > "${SPACK_USER_CONFIG_PATH}/repos.yaml"
        fi
    fi
}
init_workflow_user_scope
export SPACK_DOWNLOAD_URL="https://github.com/spack/spack/releases/download/v${SPACK_VERSION}/spack-${SPACK_VERSION}.tar.gz"

# ── 鲲鹏 spack repo 相关常量 ──────────────────────────────────────────────────
export KP_SPACK_REPO_URL="https://gitcode.com/wmrd/kp-spack.git"
export KP_SPACK_BRANCH="kunpeng920prof"
export KP_SPACK_REPO_DIR="${SPACK_WORKFLOW_DIR}/kp-spack-repo"
export KP_SPACK_REPO_NAMESPACE="kunpeng920prof"

# ── 确保 spack 可用（不存在则自动下载安装） ───────────────────────────────────
ensure_spack() {
    log_step "确保 Spack 可用（无条件安装到 ${SPACK_WORKFLOW_DIR}/）..."

    # 无条件在 workflow/spack-workflow/ 下安装独立实例，不借用系统已有的 spack

    # 检查 workflow/spack-workflow/spack-1.2.1 是否已存在
    if [ -f "${SPACK_DIR}/bin/spack" ]; then
        log_info "工作流 Spack 已安装在 ${SPACK_DIR}，直接启用"
        source "${SPACK_DIR}/share/spack/setup-env.sh"
        return 0
    fi

    # 需要下载安装
    log_step "Spack 未找到，开始自动安装到 ${SPACK_WORKFLOW_DIR}/"

    mkdir -p "$SPACK_WORKFLOW_DIR"
    cd "$SPACK_WORKFLOW_DIR"

    local tarball="spack-${SPACK_VERSION}.tar.gz"

    # 下载（如已存在则跳过）
    if [ -f "$tarball" ]; then
        log_info "tarball 已存在: ${tarball}"
    else
        log_info "下载 Spack ${SPACK_VERSION}..."
        log_info "URL: ${SPACK_DOWNLOAD_URL}"
        if ! curl -L -o "$tarball" "$SPACK_DOWNLOAD_URL" 2>&1; then
            log_error "下载失败！请检查网络连接"
            return 1
        fi
    fi

    # 校验文件大小（至少 1MB）
    local fsize
    fsize=$(stat -c%s "$tarball" 2>/dev/null || stat -f%z "$tarball" 2>/dev/null || echo 0)
    if [ "$fsize" -lt 1000000 ]; then
        log_error "下载文件过小 (${fsize} bytes)，可能不完整"
        return 1
    fi
    log_info "下载完成: ${tarball} ($((fsize / 1024 / 1024)) MB)"

    # 解压
    log_info "解压 ${tarball}..."
    tar -xzf "$tarball" -C "$SPACK_WORKFLOW_DIR"
    if [ ! -d "${SPACK_DIR}" ]; then
        log_error "解压后未找到 ${SPACK_DIR}"
        return 1
    fi

    # 加载 spack 环境
    log_info "加载 Spack 环境..."
    source "${SPACK_DIR}/share/spack/setup-env.sh"

    # 验证
    local ver
    ver=$(spack --version 2>/dev/null || echo "unknown")
    log_info "Spack 安装成功: ${ver}"
    log_info "安装路径: ${SPACK_DIR}"
    log_info "配置目录: ${SPACK_ETC}"

    cd "$WORKFLOW_ROOT"
    return 0
}

# ── 克隆鲲鹏 spack 仓库（kp-spack） ──────────────────────────────────────────
clone_kp_spack_repo() {
    log_step "配置鲲鹏 spack 仓库 (kp-spack)..."

    # 如果已存在且有 repo.yaml，跳过克隆
    local repo_yaml="${KP_SPACK_REPO_DIR}/kunpeng920prof/spack_repo/kunpeng920prof/repo.yaml"
    if [ -f "$repo_yaml" ]; then
        log_info "kp-spack 仓库已存在: ${KP_SPACK_REPO_DIR}"
        # 确保是最新
        cd "$KP_SPACK_REPO_DIR"
        git pull --quiet 2>/dev/null || log_warn "git pull 失败，使用现有版本"
        cd "$WORKFLOW_ROOT"
        return 0
    fi

    log_info "克隆 kp-spack 仓库 (branch: ${KP_SPACK_BRANCH})..."
    log_info "URL: ${KP_SPACK_REPO_URL}"

    mkdir -p "$SPACK_WORKFLOW_DIR"

    if ! git clone --depth 1 -b "$KP_SPACK_BRANCH" "$KP_SPACK_REPO_URL" "$KP_SPACK_REPO_DIR" 2>&1; then
        log_error "克隆 kp-spack 失败"
        return 1
    fi

    # 验证仓库结构
    if [ ! -f "$repo_yaml" ]; then
        log_error "克隆成功但未找到 repo.yaml: ${repo_yaml}"
        log_error "请检查仓库结构"
        return 1
    fi

    log_info "kp-spack 克隆成功"
    log_info "repo.yaml: ${repo_yaml}"

    # 列出可用包
    local pkg_dir="${KP_SPACK_REPO_DIR}/kunpeng920prof/spack_repo/kunpeng920prof/packages"
    if [ -d "$pkg_dir" ]; then
        local pkg_count
        pkg_count=$(ls -d "${pkg_dir}"/*/ 2>/dev/null | wc -l || echo 0)
        log_info "可用包数: ${pkg_count}"
    fi

    cd "$WORKFLOW_ROOT"
    return 0
}

# ── 获取 kp-spack repo 路径（供其他脚本引用） ─────────────────────────────────
get_kp_repo_path() {
    echo "${KP_SPACK_REPO_DIR}/kunpeng920prof/spack_repo/kunpeng920prof"
}

# ── 检测 CPU 短名（用于本地 repo 命名） ──────────────────────────────────────
# 从 lscpu "Model name" 提取鲲鹏型号，如 "Kunpeng 920 72F8" → "kunpeng920F"
# 目标：repo namespace 确定性、可重建、跨阶段一致
detect_cpu_shortname() {
    local model
    model=$(lscpu 2>/dev/null | grep "Model name" | awk -F: '{print $2}' | xargs || echo "")
    local shortname

    case "$model" in
        *[Kk]unpeng*920*)
            shortname="kunpeng920F"
            ;;
        *[Kk]unpeng*916*)
            shortname="kunpeng916"
            ;;
        *[Kk]unpeng*)
            # 其他鲲鹏型号，提取数字部分
            shortname=$(echo "$model" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g' | head -c 16)
            [ -z "$shortname" ] && shortname="kunpeng"
            ;;
        *)
            # 非鲲鹏：用 aarch64 兜底
            shortname="aarch64"
            ;;
    esac

    echo "$shortname"
}

# ── 本地 repo 常量（由 detect_cpu_shortname 派生） ────────────────────────────
# 在 source lib_common.sh 时不立即求值，由 create_local_repo 调用时设置
export LOCAL_REPO_DIR=""
export LOCAL_REPO_NAMESPACE=""

# ── 创建本地 repo（stage3 自写 package.py 的存放位置） ───────────────────────
# 命名规则：<spack-workflow>/<cpu_shortname>-repo/spack_repo/<cpu_shortname>_workflow
#   例如：spack-workflow/kunpeng920F-repo/spack_repo/kunpeng920F_workflow/
# ⚠ spack 要求仓库路径下必须包含 spack_repo/<namespace>/ 子目录，
#    repo.yaml 和 packages/ 放在 spack_repo/<namespace>/ 内。
# 设计原因：各阶段像独立对话，不共享运行时变量；
#   repo 路径通过 repos.yaml（spack 持久化）传递，
#   stage3 调用 get_local_repo_path() 获取路径，不依赖环境变量。
create_local_repo() {
    log_step "创建本地 spack repo（存放自写 package.py）..."

    local cpu_shortname
    cpu_shortname=$(detect_cpu_shortname)
    # namespace 必须全小写、且与 spack_repo/<ns>/ 目录名一致：本机磁盘现状是
    # kunpeng920f_workflow，而 detect_cpu_shortname 对 920F 返回大写 F（该分支无小写化）
    local ns_shortname
    ns_shortname=$(echo "$cpu_shortname" | tr '[:upper:]' '[:lower:]')
    export LOCAL_REPO_NAMESPACE="${ns_shortname}_workflow"
    # repo 根目录
    local repo_root="${SPACK_WORKFLOW_DIR}/${cpu_shortname}-repo"
    # spack 要求的 spack_repo/<namespace>/ 子目录
    export LOCAL_REPO_DIR="${repo_root}/spack_repo/${LOCAL_REPO_NAMESPACE}"

    log_info "CPU 短名: ${cpu_shortname}"
    log_info "本地 repo 根目录: ${repo_root}"
    log_info "本地 repo spack 路径: ${LOCAL_REPO_DIR}"
    log_info "本地 repo namespace: ${LOCAL_REPO_NAMESPACE}"

    # 创建目录结构
    mkdir -p "${LOCAL_REPO_DIR}/packages"

    # 写 repo.yaml（如不存在或 namespace 不匹配则覆写）
    local repo_yaml="${LOCAL_REPO_DIR}/repo.yaml"
    if [ -f "$repo_yaml" ]; then
        local existing_ns
        existing_ns=$(grep namespace "$repo_yaml" 2>/dev/null | awk -F"'" '{print $2}' || echo "")
        if [ "$existing_ns" = "$LOCAL_REPO_NAMESPACE" ]; then
            log_info "repo.yaml 已存在且 namespace 匹配，跳过"
        else
            log_warn "repo.yaml namespace 不匹配(已有: ${existing_ns})，覆写"
            cat > "$repo_yaml" << EOF
repo:
  namespace: '${LOCAL_REPO_NAMESPACE}'
  api: v2.4
EOF
        fi
    else
        log_info "创建 repo.yaml..."
        cat > "$repo_yaml" << EOF
repo:
  namespace: '${LOCAL_REPO_NAMESPACE}'
  api: v2.4
EOF
    fi

    # 注册到 spack（如尚未注册）
    if command -v spack &>/dev/null; then
        if spack repo list 2>/dev/null | grep -q "${LOCAL_REPO_DIR}"; then
            log_info "本地 repo 已注册到 spack，跳过"
        else
            log_info "注册本地 repo 到 spack..."
            spack repo add "${LOCAL_REPO_DIR}" 2>/dev/null || log_warn "spack repo add 失败（可能已注册）"
        fi
    fi

    log_info "本地 repo 创建完成: ${LOCAL_REPO_DIR}"
    return 0
}

# ── 获取本地 repo 路径（供其他脚本引用） ─────────────────────────────────────
# 优先用环境变量；无则从 repos.yaml 读取（跨阶段时环境变量不存在）
get_local_repo_path() {
    if [ -n "${LOCAL_REPO_DIR:-}" ] && [ -d "${LOCAL_REPO_DIR}" ]; then
        echo "${LOCAL_REPO_DIR}"
        return 0
    fi

    # 1) 工作流私有 user scope 的 repos.yaml（map 形态：`<ns>: <path>`）
    local path=""
    local user_repos="${SPACK_USER_CONFIG_PATH}/repos.yaml"
    if [ -f "$user_repos" ]; then
        path=$(sed -n 's/^[[:space:]]*[A-Za-z0-9_.-]*_workflow:[[:space:]]*\(.*\)$/\1/p' \
               "$user_repos" | head -1 | tr -d ' "' || true)
    fi

    # 2) 回退：从 spack 合并配置里按 map 形态取
    #    ⚠ 老写法按 '- 路径' 列表形态解析，而 spack 1.2.1 返回 map 形态，实测恒取不到
    if [ -z "$path" ]; then
        path=$(spack config get repos 2>/dev/null \
               | sed -n 's/^[[:space:]]*[A-Za-z0-9_.-]*_workflow:[[:space:]]*\(.*\)$/\1/p' \
               | head -1 | tr -d ' "' || true)
    fi
    if [ -n "$path" ] && [ -d "$path" ]; then
        echo "$path"
        return 0
    fi

    return 1
}

# ── 配置 repos.yaml（鲲鹏 repo 优先于 builtin） ──────────────────────────────
# 注意：本地 repo 由 stage3 调用 create_local_repo() 创建后自行注册到 spack，
#       stage1 的 repos.yaml 只包含鲲鹏 repo + builtin
configure_repos_yaml() {
    log_step "配置 repos.yaml（鲲鹏 repo 优先于 builtin）..."

    local kp_repo_path
    kp_repo_path=$(get_kp_repo_path)

    local repos_yaml="${SPACK_ETC}/repos.yaml"

    cat > "$repos_yaml" << EOF
repos:
  - ${kp_repo_path}
EOF

    log_info "repos.yaml 已写入: ${repos_yaml}"
    log_info "鲲鹏 repo 路径: ${kp_repo_path}"

    # 验证 spack 能识别 repo
    if command -v spack &>/dev/null; then
        log_info "验证 spack repo list:"
        spack repo list 2>&1 | head -10
    fi

    return 0
}

# ── 配置 config.yaml（基本配置） ──────────────────────────────────────────────
configure_config_yaml() {
    log_step "配置 config.yaml..."

    local config_yaml="${SPACK_ETC}/config.yaml"

    cat > "$config_yaml" << 'EOF'
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

    log_info "config.yaml 已写入: ${config_yaml}"
    return 0
}

# ── 配置 packages.yaml（BLAS/LAPACK/编译器指向） ─────────────────────────────
configure_packages_yaml() {
    log_step "配置 packages.yaml..."

    local packages_yaml="${SPACK_ETC}/packages.yaml"

    cat > "$packages_yaml" << 'EOF'
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

    log_info "packages.yaml 已写入: ${packages_yaml}"
    return 0
}

# ── 安装 HPCKit（通过 spack install hpckit） ──────────────────────────────────
install_hpckit() {
    log_step "安装 HPCKit（鲲鹏 HPC 开发套件）..."

    if ! command -v spack &>/dev/null; then
        log_error "spack 不可用，无法安装 hpckit"
        return 1
    fi

    # 检查是否已安装
    if spack find hpckit &>/dev/null 2>&1; then
        log_info "hpckit 已安装"
        spack find -l hpckit 2>/dev/null | head -5
        return 0
    fi

    log_info "开始安装 hpckit@26.0.RC1..."

    local nproc
    nproc=$(nproc 2>/dev/null || echo 8)

    # 先 spec 看看
    log_info "spec 预览:"
    spack spec hpckit@26.0.RC1 2>&1 | head -30 || true

    # 安装
    if spack install -j"$nproc" hpckit@26.0.RC1 2>&1; then
        log_info "hpckit 安装成功"
        spack find -l hpckit 2>/dev/null | head -5
        return 0
    else
        log_error "hpckit@26.0.RC1 安装失败（packages.yaml 已将 hpckit 锁定为 @26.0.RC1）"
        return 1
    fi
}

# ── 注册 HPCKit 中的 gcc 和 bisheng 编译器到 spack ────────────────────────────
register_hpckit_compilers() {
    log_step "注册 HPCKit 编译器（gcc + bisheng）到 spack..."

    if ! command -v spack &>/dev/null; then
        log_error "spack 不可用"
        return 1
    fi

    # 找到 hpckit 安装路径
    local hpckit_prefix
    hpckit_prefix=$(spack location -i hpckit 2>/dev/null || echo "")
    if [ -z "$hpckit_prefix" ]; then
        log_error "未找到 hpckit 安装路径，请先安装 hpckit"
        return 1
    fi
    log_info "hpckit 安装路径: ${hpckit_prefix}"

    # 确定版本目录
    local hpckit_ver_dir
    hpckit_ver_dir=$(ls -d "${hpckit_prefix}/HPCKit/"*/ 2>/dev/null | head -1 | sed 's|/$||')
    if [ -z "$hpckit_ver_dir" ]; then
        hpckit_ver_dir="${hpckit_prefix}/HPCKit/$(ls ${hpckit_prefix}/HPCKit/ 2>/dev/null | head -1)"
    fi
    log_info "HPCKit 版本目录: ${hpckit_ver_dir}"

    # 编译器 bin 目录
    local gcc_bin="${hpckit_ver_dir}/compiler/gcc/bin"
    local bisheng_bin="${hpckit_ver_dir}/compiler/bisheng/bin"

    # ── 注册前清理「同版本」陈旧 external（关键，否则 find 会静默跳过）──────────
    # spack compiler find 按「包名+版本」去重：user scope 里若已存在同版本编译器
    # （常见成因：旧 HPCKit 版本 26.1.RC1/25.1.0 的 external，或从 /root/.spack 迁移
    #  进来的旧前缀），find 对当前 hpckit 前缀的同版本只会报 "Found no new compilers"，
    #  新路径写不进 packages.yaml，%gcc/%llvm 仍解析到旧前缀（实测：llvm@19.1.7 停在
    #  26.1.RC1 旧树、gcc@12.3.1 停在 /opt/HPCKit/25.1.0）。
    # 故先按检测到的版本移除同名 external，再 find 重新登记为当前 hpckit 前缀。
    local _gcc_ver _clang_ver
    if [ -x "${gcc_bin}/gcc" ]; then
        _gcc_ver=$("${gcc_bin}/gcc" -dumpfullversion 2>/dev/null || true)
        if [ -n "$_gcc_ver" ]; then
            spack compiler remove --scope=user "gcc@${_gcc_ver}" >/dev/null 2>&1 || true
        fi
    fi
    if [ -x "${bisheng_bin}/clang" ]; then
        _clang_ver=$("${bisheng_bin}/clang" --version 2>/dev/null \
            | grep -oE 'version [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $2}' || true)
        if [ -n "$_clang_ver" ]; then
            spack compiler remove --scope=user "llvm@${_clang_ver}" >/dev/null 2>&1 || true
        fi
    fi

    # 注册 GCC 编译器
    if [ -d "$gcc_bin" ]; then
        log_info "注册 GCC 编译器: ${gcc_bin}"
        # 用 user scope（已隔离到 spack-workflow/user-config），不要用 site scope：
        # spack 1.x 的编译器是 external 包，写 site 目录既不符合语义也不随工作流搬迁
        spack compiler find --scope=user "$gcc_bin" 2>&1 || log_warn "GCC 注册可能失败"
    else
        log_warn "GCC bin 目录不存在: ${gcc_bin}"
    fi

    # 注册 BiSheng 编译器（注意：spack 中注册名为 llvm，不是 bisheng）
    if [ -d "$bisheng_bin" ]; then
        log_info "注册 BiSheng 编译器: ${bisheng_bin}"
        spack compiler find --scope=user "$bisheng_bin" 2>&1 || log_warn "BiSheng 注册可能失败"
    else
        log_warn "BiSheng bin 目录不存在: ${bisheng_bin}"
        # 尝试在 hmpi 的 bisheng 路径下找
        local alt_bisheng="${hpckit_ver_dir}/hmpi/bisheng/release/hmpi/bin"
        if [ -d "$alt_bisheng" ]; then
            log_info "尝试备用 BiSheng 路径: ${alt_bisheng}"
        fi
    fi

    # 断言：HPCKit 编译器（gcc/bisheng）必须出现在工作流私有 user scope 里
    if grep -q "HPCKit" "${SPACK_USER_CONFIG_PATH}/packages.yaml" 2>/dev/null; then
        log_info "✅ HPCKit 编译器已落盘: ${SPACK_USER_CONFIG_PATH}/packages.yaml"
    else
        log_warn "⚠ 工作流 user scope 的 packages.yaml 里没有 HPCKit 编译器定义 —— %gcc/%llvm 会落到系统编译器"
    fi

    # 列出已注册编译器
    echo ""
    log_info "已注册编译器:"
    spack compiler list 2>/dev/null | grep -iE "gcc|clang|bisheng|llvm" || spack compiler list

    # 将编译器信息写入 packages.yaml 的 compilers 部分
    # 通过 spack compiler find 已经自动注册到 compilers.yaml
    # 这里额外在 packages.yaml 中设置偏好
    log_info "更新 packages.yaml 编译器偏好..."
    local packages_yaml="${SPACK_ETC}/packages.yaml"

    # 确保 packages.yaml 中有编译器偏好
    if ! grep -q "compiler:" "$packages_yaml" 2>/dev/null; then
        # 在 all: 下面添加 compiler 行
        # 由于 packages.yaml 已经在 configure_packages_yaml 中写好，这里只做验证
        log_info "packages.yaml 已包含编译器偏好配置"
    fi

    return 0
}

# ── HPCKit 环境自动探测与加载 ──────────────────────────────────────────────────
load_hpckit() {
    log_step "探测 HPCKit 环境路径..."

    # 优先通过 spack load 加载
    if command -v spack &>/dev/null; then
        if spack find hpckit &>/dev/null 2>&1; then
            spack load hpckit 2>/dev/null || true
        fi
    fi

    # 探测 GCC（HPCKit 自带）
    local found_gcc
    found_gcc=$(find /opt /home -maxdepth 8 -path "*/compiler/gcc/bin/gcc" \
        -not -path "*/package/*" 2>/dev/null | head -1)

    if [ -n "$found_gcc" ]; then
        local hpckit_base
        hpckit_base="$(echo "$found_gcc" | sed 's|/compiler/gcc/bin/gcc||')"
        local gcc_dir="${hpckit_base}/compiler/gcc"
        local hmpi_dir="${hpckit_base}/hmpi/gcc/release/hmpi"

        export HPCKIT_BASE="$hpckit_base"
        export GCC_DIR="$gcc_dir"
        export HMPI_DIR="$hmpi_dir"

        export PATH="${gcc_dir}/bin:${hmpi_dir}/bin:${PATH}"
        export OPAL_PREFIX="${hmpi_dir}"
        export LD_LIBRARY_PATH="${hmpi_dir}/lib:${gcc_dir}/lib64:${gcc_dir}/lib64_public:${LD_LIBRARY_PATH:-}"
        export OMP_NUM_THREADS=1

        log_info "HPCKit 已加载: $(gcc --version | head -1)"
        log_info "HMPI mpicc: $(which mpicc 2>/dev/null || echo 'not found')"
        return 0
    else
        log_warn "未找到 HPCKit，将使用系统编译器"
        return 1
    fi
}

# ── 探测 BiSheng 编译器 ───────────────────────────────────────────────────────
find_bisheng() {
    local found_bisheng
    found_bisheng=$(find /opt /home -maxdepth 8 -path "*/compiler/bisheng/bin/clang" \
        -not -path "*/package/*" 2>/dev/null | head -1)
    if [ -n "$found_bisheng" ]; then
        export BISHENG_DIR="$(echo "$found_bisheng" | sed 's|/bin/clang||')"
        export BISHENG_BIN="$found_bisheng"
        log_info "BiSheng 编译器: $found_bisheng ($(${found_bisheng} --version | head -1))"
        return 0
    else
        log_warn "未找到 BiSheng 编译器"
        return 1
    fi
}

# ── 校验架构 ──────────────────────────────────────────────────────────────────
check_arch() {
    local arch
    arch=$(uname -m)
    if [ "$arch" != "aarch64" ]; then
        log_error "当前架构为 $arch，本工作流仅支持 aarch64"
        return 1
    fi
    log_info "架构校验通过: aarch64"
    return 0
}

# ── spack 命令封装 ────────────────────────────────────────────────────────────
spack_cmd() {
    if ! command -v spack &>/dev/null; then
        log_error "spack 不在 PATH 中"
        return 1
    fi
    spack "$@"
}

# ── 安装单个包并记录 ──────────────────────────────────────────────────────────
# 用法: install_and_log <pkg_spec> <log_file>
install_and_log() {
    local spec="$1"
    local log_file="$2"
    local pkg_name
    pkg_name=$(echo "$spec" | awk '{print $1}' | sed 's/[+^].*//')

    log_step "安装 $spec ..."

    # dry-run spec
    if ! spack spec "$spec" &>/dev/null; then
        log_error "spec 解析失败: $spec"
        echo "| $pkg_name | — | — | ❌ spec失败 | — |" >> "$log_file"
        return 1
    fi

    # 安装
    local nproc
    nproc=$(nproc)
    if spack install -j"$nproc" "$spec" 2>&1 | tee -a /tmp/spack_install_${pkg_name}.log; then
        local hash
        hash=$(spack find -l "$pkg_name" 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '[]')
        local version
        version=$(spack find --format "{version}" "$pkg_name" 2>/dev/null | head -1)
        log_info "安装成功: $pkg_name @${version} /${hash}"
        echo "| $pkg_name | ${version:-?} | ${hash:-?} | ✅ 成功 | — |" >> "$log_file"
        return 0
    else
        log_error "安装失败: $spec"
        echo "| $pkg_name | — | — | ❌ 安装失败 | $(tail -3 /tmp/spack_install_${pkg_name}.log | tr '\n' ' ') |" >> "$log_file"
        return 1
    fi
}

# ── NUMA 拓扑记录 ────────────────────────────────────────────────────────────
record_numa() {
    local outfile="$1"
    {
        echo ""
        echo "## NUMA 拓扑"
        echo ""
        echo '```'
        numactl -H 2>/dev/null || echo "numactl 不可用"
        echo '```'
        echo ""
    } >> "$outfile"
}
