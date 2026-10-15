#!/bin/bash
#===============================================================================
# 阶段 5：交付
# 目标：对每个已安装软件生成一个 README.md（安装命令 + 依赖树 + 描述）
#       放到对应的 package 目录里（spack install prefix 或 manual-build 目录）
# 用法：bash deliver.sh
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib_common.sh"

log_step "=== 阶段 5：交付 — 生成软件说明文档 ==="

if ! command -v spack &>/dev/null; then
    log_error "spack 不可用"
    exit 1
fi

# ── 读取 install_log.md 中的已安装包列表 ─────────────────────────────────────
INSTALL_LOG="${SCRIPT_DIR}/../stage3-install/install_log.md"
DELIVER_DIR="${SCRIPT_DIR}"

if [ ! -f "$INSTALL_LOG" ]; then
    log_error "安装日志不存在: $INSTALL_LOG"
    exit 1
fi

# 获取所有成功安装的包（去重）
SUCCESS_PKGS=$(grep '✅' "$INSTALL_LOG" 2>/dev/null | awk -F'|' '{print $2}' | xargs | tr ' ' '\n' | sort -u | grep -v '^$' || echo "")

if [ -z "$SUCCESS_PKGS" ]; then
    log_warn "安装日志中无成功安装的包"
    exit 0
fi

PKG_COUNT=$(echo "$SUCCESS_PKGS" | wc -l)
log_info "共 ${PKG_COUNT} 个已安装软件需要生成文档"
echo ""

# ── 为每个包生成说明文档 ─────────────────────────────────────────────────────
for pkg_name in $SUCCESS_PKGS; do
    pkg_name=$(echo "$pkg_name" | xargs)
    [ -z "$pkg_name" ] && continue

    log_step "生成文档: ${pkg_name}"

    # 获取安装信息
    # 一条 format 拿全字段：既避免「A 实例的版本 + B 实例的 hash」混搭（本机同包最多 6 实例），
    # 也避免 `spack location -i <name>` 在同包多实例时报 "matches multiple packages"
    PKG_LINE=$(spack find --format "{name}|{version}|{compiler}|{hash}|{prefix}" "$pkg_name" 2>/dev/null | head -1 || true)
    if [ -z "$PKG_LINE" ]; then
        # 可能是手动安装的包，从 install_log 读信息
        log_warn "  spack find 未找到 ${pkg_name}，可能为手动安装，跳过"
        continue
    fi
    IFS='|' read -r PKG_NAME PKG_VERSION PKG_COMPILER_FULL PKG_HASH PKG_PREFIX <<< "${PKG_LINE}"
    # {compiler} 会带上编译器自身 hash（形如 gcc@12.3.1/7gxioh…），只保留 name@version
    PKG_COMPILER="${PKG_COMPILER_FULL%%/*}"
    PKG_SPEC="${PKG_NAME}@${PKG_VERSION} ${PKG_COMPILER}"
    PKG_HASH_SPEC="/${PKG_HASH:0:7}"    # hash 形式唯一定位实例（实测 spack find /wefpq24 可解析）

    if [ ! -d "${PKG_PREFIX:-}" ]; then
        log_error "  无法定位 ${pkg_name} 的安装目录（prefix='${PKG_PREFIX:-空}'），跳过"
        continue
    fi

    # 获取依赖树
    # ⚠ 三种命令实测（2026-10-09）：`spack deps` 不是命令；`spack dependencies --transitive <name>`
    #   在本 spack 构建里返回**整仓 673 个包**的垃圾列表（不是该包的依赖树，且会让
    #   「鲲鹏优化组件」章节给每个包都套上 hmpi/kpblas/kplapack 的错误结论）；
    #   `spack dependencies --transitive /<hash>` 报 kp repo 的 package 找不到。
    #   正确做法是用 hash 唯一定位实例的 `spack find -d`。
    DEP_TREE=$(spack find -d "$PKG_HASH_SPEC" 2>/dev/null || echo "无法获取依赖树")

    # 获取依赖中的鲲鹏优化组件
    KP_DEPS=$(spack find -d "$PKG_HASH_SPEC" 2>/dev/null | grep -oiE 'hmpi|hpckit|kpblas|kpfft|kpfftw|kpkml|kpksvml|kpkupl|kplapack|kpscalapack|kpscasolver|kpsolver|kpspblas|kpvml' | sort -u || echo "")

    # 获取 spack info 摘要（描述 + homepage）
    PKG_INFO=$(spack info "$pkg_name" 2>/dev/null || echo "无信息")
    PKG_DESC=$(echo "$PKG_INFO" | grep -A1 "Description:" | tail -1 | xargs 2>/dev/null || echo "无描述")
    PKG_HOMEPAGE=$(echo "$PKG_INFO" | grep "Homepage:" | awk '{print $2}' || echo "无")

    # 生成 README.md
    README_PATH="${PKG_PREFIX}/README.md"

    # 构建鲲鹏优化组件章节
    KP_SECTION=""
    if [ -n "$KP_DEPS" ]; then
        KP_SECTION="
## 鲲鹏优化组件

本软件已链接以下鲲鹏920优化组件：

| 组件 | 功能 |
|------|------|"
        for kp in $KP_DEPS; do
            case "$kp" in
                hmpi)         KP_SECTION="${KP_SECTION}
| hmpi | 鲲鹏优化MPI通信库 |" ;;
                hpckit)       KP_SECTION="${KP_SECTION}
| hpckit | HPC开发套件元包(编译器+MPI+数学库) |" ;;
                kpblas)       KP_SECTION="${KP_SECTION}
| kpblas | 基础线性代数(矩阵乘/向量运算) |" ;;
                kpspblas)     KP_SECTION="${KP_SECTION}
| kpspblas | 稀疏矩阵BLAS |" ;;
                kplapack)     KP_SECTION="${KP_SECTION}
| kplapack | 高级线性代数求解(特征值/SVD) |" ;;
                kpscalapack)  KP_SECTION="${KP_SECTION}
| kpscalapack | 分布式并行LAPACK |" ;;
                kpscasolver)  KP_SECTION="${KP_SECTION}
| kpscasolver | 分布式求解器 |" ;;
                kpsolver)     KP_SECTION="${KP_SECTION}
| kpsolver | 直接求解器 |" ;;
                kpfft)        KP_SECTION="${KP_SECTION}
| kpfft | 快速傅里叶变换 |" ;;
                kpfftw)       KP_SECTION="${KP_SECTION}
| kpfftw | FFTW接口兼容层 |" ;;
                kpvml)        KP_SECTION="${KP_SECTION}
| kpvml | 向量数学函数库 |" ;;
                kpksvml)      KP_SECTION="${KP_SECTION}
| kpksvml | 短向量数学函数库 |" ;;
                kpkupl)       KP_SECTION="${KP_SECTION}
| kpkupl | 鲲鹏通用性能库 |" ;;
                kpkml)        KP_SECTION="${KP_SECTION}
| kpkml | KML元包(聚合BLAS/LAPACK/FFT/向量等子组件) |" ;;
            esac
        done
    fi

    cat > "$README_PATH" << READMEEOF
# ${pkg_name}

## 基本信息

| 项目 | 值 |
|------|-----|
| 软件名 | ${pkg_name} |
| 版本 | ${PKG_VERSION} |
| 编译器 | ${PKG_COMPILER:-default} |
| hash | ${PKG_HASH} |
| 安装路径 | ${PKG_PREFIX} |
| 主页 | ${PKG_HOMEPAGE} |

## 描述

${PKG_DESC}
${KP_SECTION}
## 安装命令

\`\`\`bash
# 加载 spack 环境
source ${SPACK_DIR}/share/spack/setup-env.sh

# 精确复现本实例（推荐：hash 唯一定位，避免同包多版本/多编译器歧义）
spack install ${PKG_HASH_SPEC}

# 或按 name/版本/编译器重装（会重新具体化；BiSheng 在 spack 中的注册名是 llvm，
# 写 %bisheng 会报 "cannot depend on bisheng"）
spack install ${PKG_SPEC}

# 加载使用
spack load ${PKG_HASH_SPEC}
\`\`\`

## 依赖树

\`\`\`
${DEP_TREE}
\`\`\`

## 加载方式

\`\`\`bash
spack load ${PKG_HASH_SPEC}
\`\`\`

或通过 module：

\`\`\`bash
module load ${pkg_name}
\`\`\`
READMEEOF

    log_info "  ✅ 文档已生成: ${README_PATH}"

    # 同时在 deliver 目录存一份副本
    cp "$README_PATH" "${DELIVER_DIR}/${pkg_name}.md" 2>/dev/null || true

    echo ""
done

# ── 汇总 ──────────────────────────────────────────────────────────────────
echo ""
echo "=== 交付汇总 ==="
echo "已生成文档数: $(ls "${DELIVER_DIR}"/*.md 2>/dev/null | grep -v DESCRIPTION | grep -v AI_INSTRUCTION | wc -l || echo 0)"
echo "文档位置: ${DELIVER_DIR}/<软件名>.md（同时复制到各软件安装路径下）"
echo ""
log_info "每个软件的 README.md 包含：安装命令 + 依赖树 + 描述 + 加载方式"
log_step "=== 阶段 5 完成 ==="
