#!/bin/bash
#===============================================================================
# 阶段 3：安装软件
# 读取 packages_to_install.yaml（CSV 格式），对每个软件按编译器安装
#
# 用法：bash install_batch.sh              (安装全部)
#       bash install_batch.sh gcc          (只装 gcc 版本)
#       bash install_batch.sh bisheng      (只装 bisheng 版本，映射为 %llvm)
#       bash install_batch.sh <包名>        (只装指定包)
#       bash install_batch.sh --from-3.5   (处理 stage3.5 回传的包)
#
# 编译器名称映射：
#   清单中的 "bisheng" → spack 的 %llvm（BiSheng 在 spack 中注册名为 llvm，非 bisheng）
#
# 重试规则：
#   - 已有包直接安装失败 → 复制官方 package.py 到本地 repo 修改重试（最多3次）
#   - 包不存在 → 编写新 package.py 安装重试（最多3次）
#   - 3次均败 → 写入 handoff_to_3.5.md，转 stage3.5 手动编译
#   - stage3.5 回传 → 据编译命令写 package.py（最多2次重试）
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib_common.sh"

PACKAGES_FILE="${SCRIPT_DIR}/../stage2-packages/packages_to_install.yaml"
LOG_FILE="${SCRIPT_DIR}/install_log.md"
HANDOFF_35_FILE="${SCRIPT_DIR}/handoff_to_3.5.md"
HANDOFF_FROM_35_FILE="${SCRIPT_DIR}/../stage3.5-manual-build/handoff_to_3.md"

# ── 最大重试次数配置 ─────────────────────────────────────────────────────────
MAX_RETRY_PACKAGE_PY=3    # 路径A2/B：修改 package.py 重试次数
MAX_RETRY_FROM_MANUAL=2   # 路径C：据手动编译命令写 package.py 重试次数

# ── 命令行参数解析 ────────────────────────────────────────────────────────────
FROM_35=false
FILTER="all"
if [ "${1:-}" = "--from-3.5" ]; then
    FROM_35=true
    shift 2>/dev/null || true
    FILTER="${1:-all}"
elif [ -n "${1:-}" ]; then
    FILTER="$1"
fi

# ── 创建本地 repo（自写 package.py 的存放位置） ──────────────────────────────
# 基于 CPU 型号命名，如 "Kunpeng 920 72F8" → spack-workflow/kunpeng920F-repo/
# 路径结构：spack-workflow/kunpeng920F-repo/spack_repo/kunpeng920F_workflow/
# stage1 未创建本地 repo（只配置了鲲鹏 repo + builtin），stage3 负责创建并注册
create_local_repo || {
    log_error "本地 repo 创建失败，自写 package.py 将无法存放"
    echo "| 本地 repo | — | — | — | ❌ 创建失败 | — | 0 | stage3 初始化 |" >> "$LOG_FILE"
}
log_info "本地 repo: ${LOCAL_REPO_DIR}"

# ── 初始化安装日志 ────────────────────────────────────────────────────────────
init_log() {
    if [ ! -f "$LOG_FILE" ] || ! head -1 "$LOG_FILE" | grep -q "安装日志"; then
        cat > "$LOG_FILE" << 'EOF'
# 安装日志 (install_log.md)

> 由 install_batch.sh 自动维护。
> 方式：builtin=spack内置包 / package.py new=新写脚本 / package.py modified=复制官方+修改 / package.py from manual=据手动编译命令写 / 手动编译=manual build

| 包名 | 编译器 | 版本 | hash | 状态 | 方式 | 重试次数 | 备注 |
|------|--------|------|------|------|------|---------|------|
EOF
        log_info "安装日志已初始化: $LOG_FILE"
    fi
}

# ── 初始化/追加移交清单 ──────────────────────────────────────────────────────
init_handoff_35() {
    if [ ! -f "$HANDOFF_35_FILE" ]; then
        cat > "$HANDOFF_35_FILE" << 'EOF'
# Stage3 → Stage3.5 移交清单

> 由 install_batch.sh 自动生成。
> 以下包在 stage3 中 spack 安装3次重试均失败，需 stage3.5 手动编译。

| 包名 | 编译器 | 版本 | spec | 失败原因 | 源码URL | 本地package.py |
|------|--------|------|------|---------|---------|---------------|
EOF
        log_info "移交清单已初始化: $HANDOFF_35_FILE"
    fi
}

# ── 写入移交记录 ──────────────────────────────────────────────────────────────
# 用法: write_handoff_35 <包名> <编译器> <版本> <spec> <失败原因> <源码URL> <本地package.py路径>
write_handoff_35() {
    init_handoff_35
    local name="$1" compiler="$2" version="$3" spec="$4"
    local fail_reason="$5" source_url="$6" pkg_path="$7"
    echo "| ${name} | ${compiler} | ${version} | ${spec} | ${fail_reason} | ${source_url} | ${pkg_path} |" >> "$HANDOFF_35_FILE"
    log_warn "已移交 stage3.5: ${name} ${compiler}"
}

# ── 复制官方 package.py 到本地 repo ──────────────────────────────────────────
# 用法: copy_official_package <pkg_name>
copy_official_package() {
    local pkg_name="$1"
    local local_repo
    local_repo=$(get_local_repo_path) || {
        log_error "无法获取本地 repo 路径"
        return 1
    }

    local pkg_dir="${local_repo}/packages/${pkg_name}"
    mkdir -p "$pkg_dir"

    # 查找官方 package.py
    local official_dir=""
    # 用 spack 自己解析包目录：spack 1.2.1 的 builtin 不在 ${SPACK_DIR}/var/spack/repos/builtin
    # （该路径根本不存在），硬编码会让路径A2 对 builtin 包直接报「未找到官方 package.py」
    local builtin_pkg=""
    builtin_pkg=$(spack location -p "${pkg_name}" 2>/dev/null | grep '^/' | head -1 || true)
    if [ -n "$builtin_pkg" ] && [ -f "${builtin_pkg}/package.py" ] && [ "$builtin_pkg" != "$pkg_dir" ]; then
        official_dir="$builtin_pkg"
    fi

    # 在鲲鹏 repo 查找
    if [ -z "$official_dir" ]; then
        local kp_pkg
        kp_pkg=$(find "${KP_SPACK_REPO_DIR}" -path "*/packages/${pkg_name}/package.py" 2>/dev/null | head -1)
        if [ -n "$kp_pkg" ]; then
            official_dir=$(dirname "$kp_pkg")
        fi
    fi

    if [ -z "$official_dir" ]; then
        log_error "未找到 ${pkg_name} 的官方 package.py"
        return 1
    fi

    log_info "复制官方 package.py: ${official_dir} → ${pkg_dir}"

    # 复制 package.py 和补丁文件
    cp "${official_dir}/package.py" "${pkg_dir}/package.py"
    cp "${official_dir}"/*.patch "${pkg_dir}/" 2>/dev/null || true
    # 复制其他可能需要的文件（但不要覆盖 package.py）
    for f in "${official_dir}"/*; do
        local fname
        fname=$(basename "$f")
        [ "$fname" = "package.py" ] && continue
        [ -f "$f" ] && cp "$f" "${pkg_dir}/" 2>/dev/null || true
    done

    log_info "已复制到本地 repo: ${pkg_dir}"
    echo "$pkg_dir"
}

# ── 安装单个包（含重试逻辑） ──────────────────────────────────────────────────
install_one() {
    local name="$1" version="$2" compiler="$3"
    local spec="${name}"

    # 构造 spec
    if [ -n "$version" ]; then
        spec="${name}@${version}"
    fi
    if [ "$compiler" = "gcc" ]; then
        spec="${spec} %gcc"
    elif [ "$compiler" = "bisheng" ]; then
        spec="${spec} %llvm"
    fi

    log_step "安装: ${spec} (compiler=${compiler})"

    # 检查包是否存在
    local pkg_exists=false
    if spack info "$name" &>/dev/null 2>&1; then
        pkg_exists=true
    fi

    # ── 路径A：包存在，直接安装 ──────────────────────────────────────────
    if [ "$pkg_exists" = "true" ]; then
        # spec 验证
        if ! spack spec "$spec" &>/dev/null 2>&1; then
            log_warn "spec 解析失败: ${spec}，尝试简化..."
            spec="${name}"
            if [ -n "$version" ]; then
                spec="${name}@${version}"
            fi
            if [ "$compiler" = "gcc" ]; then
                spec="${spec} %gcc"
            elif [ "$compiler" = "bisheng" ]; then
                spec="${spec} %llvm"
            fi
            if ! spack spec "$spec" &>/dev/null 2>&1; then
                log_error "spec 解析失败: ${spec}"
                echo "| ${name} | ${compiler} | ${version:-默认} | — | ❌ spec失败 | builtin | 0 | — |" >> "$LOG_FILE"
                return 1
            fi
        fi  # spec 验证块结束

        # 尝试安装
        local nproc
        nproc=$(nproc 2>/dev/null || echo 8)
        local install_tmp="/tmp/spack_install_${name}_${compiler}.log"

        if spack install -j"$nproc" "$spec" 2>&1 | tee "$install_tmp"; then
            local hash version_found
            hash=$(spack find -l "$name" 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '[]' || echo "?")
            version_found=$(spack find --format "{version}" "$name" 2>/dev/null | head -1 || echo "$version")
            log_info "安装成功: ${spec} /${hash}"
            echo "| ${name} | ${compiler} | ${version_found:-${version:-默认}} | ${hash} | ✅ 成功 | builtin | 0 | — |" >> "$LOG_FILE"
            return 0
        fi

        # 直接安装失败 → 路径A2：复制+修改官方 package.py
        log_warn "直接安装失败，复制官方 package.py 到本地 repo 修改重试..."
        local local_pkg_dir
        local_pkg_dir=$(copy_official_package "$name") || {
            log_error "复制官方 package.py 失败"
            echo "| ${name} | ${compiler} | ${version:-默认} | — | ❌ 复制失败 | package.py modified | 0 | 无法复制官方package.py |" >> "$LOG_FILE"
            return 1
        }

        log_info "请 AI Agent 修改本地 repo 中的 package.py 后重新安装"
        log_info "本地 package.py: ${local_pkg_dir}/package.py"
        log_info "参考: AI_INSTRUCTION.md 路径A2 章节"

        # 路径A2：最多重试 MAX_RETRY_PACKAGE_PY 次
        local retry=0
        while [ "$retry" -lt "$MAX_RETRY_PACKAGE_PY" ]; do
            retry=$((retry + 1))
            log_step "路径A2 重试 ${retry}/${MAX_RETRY_PACKAGE_PY}: 修改 package.py 后安装"

            # 提示 AI Agent 修改 package.py
            # （实际修改由 AI Agent 执行，这里只做安装尝试）
            if spack install -j"$nproc" "$spec" 2>&1 | tee -a "$install_tmp"; then
                local hash2 version_found2
                hash2=$(spack find -l "$name" 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '[]' || echo "?")
                version_found2=$(spack find --format "{version}" "$name" 2>/dev/null | head -1 || echo "$version")
                log_info "重试 ${retry} 成功: ${spec} /${hash2}"
                echo "| ${name} | ${compiler} | ${version_found2:-${version:-默认}} | ${hash2} | ✅ 成功 | package.py modified | ${retry} | 复制官方+修改 |" >> "$LOG_FILE"
                return 0
            fi
            log_warn "重试 ${retry} 失败，继续修改..."
        done

        # 3次重试均失败 → 移交 stage3.5
        log_error "路径A2 ${MAX_RETRY_PACKAGE_PY}次重试均失败，移交 stage3.5"
        local fail_reason
        fail_reason=$(tail -5 "$install_tmp" 2>/dev/null | tr '\n' ' ' | head -c 200)
        local source_url=""
        source_url=$(spack info "$name" 2>/dev/null | grep -E "^    (url|git) " | head -1 | awk -F'"' '{print $2}' || echo "")
        write_handoff_35 "$name" "$compiler" "${version:-默认}" "$spec" "$fail_reason" "$source_url" "${local_pkg_dir}/package.py"
        echo "| ${name} | ${compiler} | ${version:-默认} | — | ⏭ 转3.5 | package.py modified | ${retry} | 3次重试失败，移交手动编译 |" >> "$LOG_FILE"
        return 1
    fi

    # ── 路径B：包不存在，编写新 package.py ────────────────────────────────
    log_warn "spack 中不存在 ${name}，需编写 package.py"
    log_info "请 AI Agent 参照 AI_INSTRUCTION.md 路径B 编写 package.py"

    # 提示 AI Agent 编写 package.py
    # （实际编写由 AI Agent 执行，这里只做框架提示）
    local local_repo
    local_repo=$(get_local_repo_path) || {
        log_error "无法获取本地 repo 路径"
        echo "| ${name} | ${compiler} | ${version:-默认} | — | ❌ repo失败 | — | 0 | 本地repo不可用 |" >> "$LOG_FILE"
        return 1
    }

    local pkg_dir="${local_repo}/packages/${name}"
    mkdir -p "$pkg_dir"
    log_info "package.py 存放位置: ${pkg_dir}/package.py"
    log_info "参考: docs/spack_package_guide.md"

    # 路径B：最多重试 MAX_RETRY_PACKAGE_PY 次（首次 + 3次修改 = 4次尝试）
    local retry=0
    local nproc
    nproc=$(nproc 2>/dev/null || echo 8)
    local install_tmp="/tmp/spack_install_${name}_${compiler}.log"

    while [ "$retry" -le "$MAX_RETRY_PACKAGE_PY" ]; do
        if [ "$retry" -eq 0 ]; then
            log_step "路径B 首次安装（需 AI Agent 先编写 package.py）"
        else
            log_step "路径B 重试 ${retry}/${MAX_RETRY_PACKAGE_PY}: 修改 package.py 后安装"
        fi

        # 检查 package.py 是否存在
        if [ ! -f "${pkg_dir}/package.py" ]; then
            log_warn "package.py 不存在，等待 AI Agent 编写..."
            # 在自动化场景中这里会等待；AI Agent 需先编写 package.py
            # 此处标记为待处理并返回，由 Agent 介入
            echo "| ${name} | ${compiler} | ${version:-默认} | — | ⏳ 待处理 | package.py new | ${retry} | 需Agent编写package.py |" >> "$LOG_FILE"
            return 1
        fi

        # spec 验证
        if ! spack spec "$spec" &>/dev/null 2>&1; then
            log_warn "spec 解析失败: ${spec}，请 AI Agent 检查 package.py"
            retry=$((retry + 1))
            continue
        fi

        # 安装
        if spack install -j"$nproc" "$spec" 2>&1 | tee "$install_tmp"; then
            local hash3 version_found3
            hash3=$(spack find -l "$name" 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '[]' || echo "?")
            version_found3=$(spack find --format "{version}" "$name" 2>/dev/null | head -1 || echo "$version")
            log_info "路径B 安装成功: ${spec} /${hash3}"
            echo "| ${name} | ${compiler} | ${version_found3:-${version:-默认}} | ${hash3} | ✅ 成功 | package.py new | ${retry} | 新写package.py |" >> "$LOG_FILE"
            return 0
        fi

        log_warn "路径B 尝试 ${retry} 失败，请 AI Agent 修改 package.py"
        retry=$((retry + 1))
    done

    # 3次重试均失败 → 移交 stage3.5
    log_error "路径B ${MAX_RETRY_PACKAGE_PY}次重试均失败，移交 stage3.5"
    local fail_reason_b
    fail_reason_b=$(tail -5 "$install_tmp" 2>/dev/null | tr '\n' ' ' | head -c 200)
    write_handoff_35 "$name" "$compiler" "${version:-默认}" "$spec" "$fail_reason_b" "" "${pkg_dir}/package.py"
    echo "| ${name} | ${compiler} | ${version:-默认} | — | ⏭ 转3.5 | package.py new | ${retry} | 3次重试失败，移交手动编译 |" >> "$LOG_FILE"
    return 1
}

# ── 处理 stage3.5 回传的包（路径C） ─────────────────────────────────────────
install_from_manual() {
    if [ ! -f "$HANDOFF_FROM_35_FILE" ]; then
        log_info "无 stage3.5 回传清单，跳过路径C"
        return 0
    fi

    log_step "处理 stage3.5 回传（路径C）"

    local local_repo
    local_repo=$(get_local_repo_path) || {
        log_error "无法获取本地 repo 路径"
        return 1
    }

    local nproc
    nproc=$(nproc 2>/dev/null || echo 8)

    # 读取回传清单
    while IFS='|' read -r _ name compiler version compile_cmd install_path build_sh _; do
        # 跳过表头和分隔线
        name=$(echo "$name" | xargs)
        [[ -z "$name" || "$name" == "包名" || "$name" == *---* ]] && continue

        compiler=$(echo "$compiler" | xargs)
        version=$(echo "$version" | xargs)
        compile_cmd=$(echo "$compile_cmd" | xargs)

        log_step "路径C: ${name} ${compiler}（据手动编译命令写 package.py）"

        local spec="${name}"
        if [ -n "$version" ] && [ "$version" != "—" ]; then
            spec="${name}@${version}"
        fi
        if [ "$compiler" = "gcc" ]; then
            spec="${spec} %gcc"
        elif [ "$compiler" = "bisheng" ]; then
            spec="${spec} %llvm"
        fi

        local pkg_dir="${local_repo}/packages/${name}"
        mkdir -p "$pkg_dir"

        log_info "请 AI Agent 根据编译命令编写 package.py"
        log_info "编译命令: ${compile_cmd}"
        log_info "package.py 存放位置: ${pkg_dir}/package.py"

        local install_tmp="/tmp/spack_install_${name}_${compiler}_c.log"
        local retry=0

        while [ "$retry" -le "$MAX_RETRY_FROM_MANUAL" ]; do
            if [ "$retry" -eq 0 ]; then
                log_step "路径C 首次安装（需 AI Agent 先编写 package.py）"
            else
                log_step "路径C 重试 ${retry}/${MAX_RETRY_FROM_MANUAL}: 修改 package.py 后安装"
            fi

            if [ ! -f "${pkg_dir}/package.py" ]; then
                log_warn "package.py 不存在，等待 AI Agent 编写..."
                echo "| ${name} | ${compiler} | ${version} | — | ⏳ 待处理 | package.py from manual | ${retry} | 据手动编译命令写 |" >> "$LOG_FILE"
                return 1
            fi

            if ! spack spec "$spec" &>/dev/null 2>&1; then
                log_warn "spec 解析失败: ${spec}"
                retry=$((retry + 1))
                continue
            fi

            if spack install -j"$nproc" "$spec" 2>&1 | tee "$install_tmp"; then
                local hash_c version_c
                hash_c=$(spack find -l "$name" 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '[]' || echo "?")
                version_c=$(spack find --format "{version}" "$name" 2>/dev/null | head -1 || echo "$version")
                log_info "路径C 安装成功: ${spec} /${hash_c}"
                echo "| ${name} | ${compiler} | ${version_c} | ${hash_c} | ✅ 成功 | package.py from manual | ${retry} | 据手动编译命令写 |" >> "$LOG_FILE"
                break
            fi

            log_warn "路径C 尝试 ${retry} 失败"
            retry=$((retry + 1))
        done

        if [ "$retry" -gt "$MAX_RETRY_FROM_MANUAL" ]; then
            log_error "路径C ${MAX_RETRY_FROM_MANUAL}次重试均失败，记为失败跳过"
            echo "| ${name} | ${compiler} | ${version} | — | ❌ 失败 | package.py from manual | ${retry} | 手动编译成功但package.py写不出 |" >> "$LOG_FILE"
        fi
    done < "$HANDOFF_FROM_35_FILE"
}

# ── 主流程 ────────────────────────────────────────────────────────────────────
init_log

# 如果 --from-3.5，只处理回传清单
if [ "$FROM_35" = "true" ]; then
    install_from_manual
    log_step "=== 阶段 3（路径C）完成 ==="
    log_info "安装日志: $LOG_FILE"
    exit 0
fi

# 正常流程：读取清单安装
if [ ! -f "$PACKAGES_FILE" ]; then
    log_error "待安装清单不存在: $PACKAGES_FILE"
    exit 1
fi

# 读取清单逐行处理
while IFS= read -r line || [ -n "$line" ]; do
    # 跳过空行和整行注释
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # 剥离行尾注释与 CR（清单模板的示例行自带中文行尾说明；不剥离时第三个字段会变成
    # "gcc # 装最新版…" 从而落入未知分支被静默跳过 —— 包被悄悄漏装）
    _raw_line="$line"
    line="${line%%#*}"
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue

    # 解析 CSV：软件名,版本,编译器
    NAME=$(echo "$line" | cut -d',' -f1 | xargs)
    VERSION=$(echo "$line" | cut -d',' -f2 | xargs)
    COMPILER=$(echo "$line" | cut -d',' -f3 | xargs)

    # 默认编译器为 both
    [ -z "$COMPILER" ] && COMPILER="both"

    log_info "处理: ${NAME} 版本=${VERSION:-默认} 编译器=${COMPILER}"

    case "$COMPILER" in
        gcc)
            if [ "$FILTER" = "all" ] || [ "$FILTER" = "gcc" ] || [ "$FILTER" = "$NAME" ]; then
                install_one "$NAME" "$VERSION" "gcc" || true
            fi
            ;;
        bisheng)
            if [ "$FILTER" = "all" ] || [ "$FILTER" = "bisheng" ] || [ "$FILTER" = "$NAME" ]; then
                install_one "$NAME" "$VERSION" "bisheng" || true
            fi
            ;;
        both)
            if [ "$FILTER" = "all" ] || [ "$FILTER" = "gcc" ] || [ "$FILTER" = "$NAME" ]; then
                install_one "$NAME" "$VERSION" "gcc" || true
            fi
            if [ "$FILTER" = "all" ] || [ "$FILTER" = "bisheng" ] || [ "$FILTER" = "$NAME" ]; then
                install_one "$NAME" "$VERSION" "bisheng" || true
            fi
            ;;
        *)
            log_error "无法解析编译器字段: '${COMPILER}'（清单行: ${_raw_line}）→ 跳过 ${NAME}"
            ;;
    esac
    echo ""
done < "$PACKAGES_FILE"

# ── 处理 stage3.5 回传（如有） ───────────────────────────────────────────────
if [ -f "$HANDOFF_FROM_35_FILE" ]; then
    log_step "检测到 stage3.5 回传清单，处理路径C..."
    install_from_manual || log_warn "路径C 存在未完成/失败项，继续收尾"
fi

# ── 汇总统计 ──────────────────────────────────────────────────────────────────
echo "--- 安装汇总 ---"
echo "成功: $(grep -c '✅' "$LOG_FILE" 2>/dev/null || echo 0)"
echo "失败: $(grep -c '❌' "$LOG_FILE" 2>/dev/null || echo 0)"
echo "待处理: $(grep -c '⏳' "$LOG_FILE" 2>/dev/null || echo 0)"
echo "转3.5: $(grep -c '⏭' "$LOG_FILE" 2>/dev/null || echo 0)"
echo ""

if [ -f "$HANDOFF_35_FILE" ]; then
    # awk 计数（grep|grep|wc 在 pipefail 下遇到只有表头的文件会让赋值失败 → set -e 中止）
    handoff_count=$(awk -F'|' '/^[[:space:]]*\|/ && $2 !~ /包名/ && $2 !~ /^[[:space:]]*-+[[:space:]]*$/ {c++} END{print c+0}' "$HANDOFF_35_FILE")
    if [ "$handoff_count" -gt 0 ]; then
        log_warn "移交 stage3.5 手动编译: ${handoff_count} 个包"
        log_info "移交清单: $HANDOFF_35_FILE"
        log_info "请执行: bash stage3.5-manual-build/manual_build.sh"
    fi
fi

log_info "安装日志: $LOG_FILE"
log_step "=== 阶段 3 完成 ==="
