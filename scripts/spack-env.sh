#!/bin/bash
#===============================================================================
# 工作流 spack 环境入口 — 供 AI Agent 手动执行 spack 命令时 source
#   source /home/zhangyuhang/workflow/scripts/spack-env.sh
# 作用：使用工作流独立 spack 实例，并把 user scope 隔离到工作流目录内，
#       避免 /root/.spack 里其他项目的 repo/包污染本工作流。
#===============================================================================
WORKFLOW_ROOT="/home/zhangyuhang/workflow"
export WORKFLOW_ROOT
export SPACK_WORKFLOW_DIR="${WORKFLOW_ROOT}/spack-workflow"
export SPACK_VERSION="1.2.1"
export SPACK_DIR="${SPACK_WORKFLOW_DIR}/spack-${SPACK_VERSION}"
export SPACK_ETC="${SPACK_DIR}/etc/spack"
export SPACK_USER_CONFIG_PATH="${SPACK_WORKFLOW_DIR}/user-config"
export SPACK_USER_CACHE_PATH="${SPACK_WORKFLOW_DIR}/user-cache"
mkdir -p "${SPACK_USER_CONFIG_PATH}" "${SPACK_USER_CACHE_PATH}"

# 与 lib_common.sh 的 init_workflow_user_scope 等价：首次使用时从全局 user scope 迁移
#   1) 编译器 externals（spack 1.x 编译器=external 包，不在工作流内则 %gcc/%llvm 失效）
#   2) 本工作流自己的本地 repo 注册（只带 *_workflow，不带其他项目的 repo）
_uc_pkgs="${SPACK_USER_CONFIG_PATH}/packages.yaml"
if [ -f /root/.spack/packages.yaml ] && grep -q "HPCKit" /root/.spack/packages.yaml; then
    if [ ! -f "$_uc_pkgs" ] || ! grep -q "HPCKit" "$_uc_pkgs"; then
        [ -f "$_uc_pkgs" ] && mv -f "$_uc_pkgs" "${_uc_pkgs}.auto-$(date +%Y%m%d-%H%M%S)"
        cp -f /root/.spack/packages.yaml "$_uc_pkgs"
        echo "[INFO] 已迁移 HPCKit 编译器 externals → ${_uc_pkgs}"
    fi
fi
if [ ! -f "${SPACK_USER_CONFIG_PATH}/repos.yaml" ]; then
    # 锚定本机型号命名，避免把其他项目的 *_workflow repo 带进来
    if [ -f /root/.spack/repos.yaml ] && grep -qE '^[[:space:]]*kunpeng[0-9a-z]*_workflow:' /root/.spack/repos.yaml; then
        { echo "repos:"; grep -E '^[[:space:]]*kunpeng[0-9a-z]*_workflow:' /root/.spack/repos.yaml; } > "${SPACK_USER_CONFIG_PATH}/repos.yaml"
        echo "[INFO] 已重建 user scope repos.yaml（仅本工作流 kunpeng*_workflow 本地 repo）"
    else
        echo "repos: {}" > "${SPACK_USER_CONFIG_PATH}/repos.yaml"
    fi
fi

source "${SPACK_DIR}/share/spack/setup-env.sh"
