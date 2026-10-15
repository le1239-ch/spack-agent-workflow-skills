#!/bin/bash
#===============================================================================
# 阶段 3.5：手动编译兜底
# 读取 stage3 移交清单（handoff_to_3.5.md），对每个失败的包执行手动编译。
# 手动编译成功后，提取编译命令写入 handoff_to_3.md 回传给 stage3。
#
# 用法：bash manual_build.sh              (处理全部移交包)
#       bash manual_build.sh <包名>        (只处理指定包)
#
# 注意：本脚本负责环境初始化和目录创建。
#       实际的手动编译由 AI Agent 参考 AI_INSTRUCTION.md 执行。
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib_common.sh"

RUN_TS="$(date +%Y%m%d-%H%M%S)"

HANDOFF_IN="${SCRIPT_DIR}/../stage3-install/handoff_to_3.5.md"
HANDOFF_OUT="${SCRIPT_DIR}/handoff_to_3.md"
LOG_FILE="${SCRIPT_DIR}/manual_build_log.md"

# ── 检查移交清单 ────────────────────────────────────────────────────────────
if [ ! -f "$HANDOFF_IN" ]; then
    log_info "无移交清单 (handoff_to_3.5.md)，stage3.5 无需执行"
    exit 0
fi

# 统计移交包数量（排除表头和注释行）
# awk 计数（grep|grep|wc 在 pipefail 下遇到只有表头的文件会返回非 0 → set -e 直接中止）
HANDOFF_COUNT=$(awk -F'|' '/^[[:space:]]*\|/ && $2 !~ /包名/ && $2 !~ /^[[:space:]]*-+[[:space:]]*$/ {c++} END{print c+0}' "$HANDOFF_IN")
if [ "$HANDOFF_COUNT" -eq 0 ]; then
    log_info "移交清单为空，stage3.5 无需执行"
    exit 0
fi

log_step "=== 阶段 3.5：手动编译兜底 ==="
log_info "移交包数量: ${HANDOFF_COUNT}"

# ── 初始化回传文件 ──────────────────────────────────────────────────────────
init_handoff_out() {
    # 每轮重置：上一轮的回传行若留着，会与本轮清单完全对不上（实测残留上一轮的
    # elmerfem 行，而本轮是 gromacs/namd），下游 stage3 路径C 会拿错包与错命令
    if [ -f "$HANDOFF_OUT" ] && [ -s "$HANDOFF_OUT" ]; then
        mv -f "$HANDOFF_OUT" "${HANDOFF_OUT}.prev-${RUN_TS}"
        log_warn "已归档上一轮回传清单: ${HANDOFF_OUT}.prev-${RUN_TS}"
    fi
    if [ ! -f "$HANDOFF_OUT" ]; then
        cat > "$HANDOFF_OUT" << 'EOF'
# Stage3.5 → Stage3 回传清单

> 由 manual_build.sh 自动生成。
> 以下包在 stage3.5 中手动编译成功，编译命令已提取，需 stage3 据此编写 package.py。

| 包名 | 编译器 | 版本 | 编译命令 | 安装路径 | 构建脚本 |
|------|--------|------|---------|---------|---------|
EOF
        log_info "回传清单已初始化: $HANDOFF_OUT"
    fi
}

# ── 初始化手动编译日志 ──────────────────────────────────────────────────────
init_log() {
    if [ -f "$LOG_FILE" ]; then
        mv -f "$LOG_FILE" "${LOG_FILE}.prev-${RUN_TS}"
    fi
    if [ ! -f "$LOG_FILE" ] || ! head -1 "$LOG_FILE" | grep -q "手动编译日志"; then
        cat > "$LOG_FILE" << 'EOF'
# 手动编译日志 (manual_build_log.md)

> 由 manual_build.sh 自动维护。
> 记录每个包的手动编译过程和结果。

| 包名 | 编译器 | 版本 | 状态 | 重试次数 | 编译命令摘要 | 备注 |
|------|--------|------|------|---------|------------|------|
EOF
        log_info "手动编译日志已初始化: $LOG_FILE"
    fi
}

init_handoff_out
init_log

# ── 加载 HPCKit 环境 ────────────────────────────────────────────────────────
load_hpckit_env() {
    local compiler="$1"
    local hpckit_prefix
    hpckit_prefix=$(spack location -i hpckit 2>/dev/null || echo "")

    if [ -z "$hpckit_prefix" ]; then
        log_error "未找到 hpckit 安装路径"
        return 1
    fi

    local hpckit_ver_dir
    hpckit_ver_dir=$(ls "${hpckit_prefix}/HPCKit/" 2>/dev/null | head -1)
    if [ -z "$hpckit_ver_dir" ]; then
        log_error "未找到 HPCKit 版本目录"
        return 1
    fi

    local setvars_dir="${hpckit_prefix}/HPCKit/${hpckit_ver_dir}"
    if [ ! -f "${setvars_dir}/setvars.sh" ]; then
        log_error "setvars.sh 不存在: ${setvars_dir}/setvars.sh"
        return 1
    fi

    log_step "加载 HPCKit 环境 (${compiler})..."
    cd "$setvars_dir"
    if [ "$compiler" = "gcc" ]; then
        source ./setvars.sh --use-gcc
    else
        source ./setvars.sh
    fi

    log_info "CC=$(which gcc 2>/dev/null || echo '?')"
    log_info "MPICC=$(which mpicc 2>/dev/null || echo '?')"
    log_info "CFLAGS 默认=${CFLAGS:-未设置}"
    return 0
}

# ── 创建构建目录 ────────────────────────────────────────────────────────────
create_build_dir() {
    local pkg_name="$1"
    local build_dir="${SPACK_WORKFLOW_DIR}/manual-build/${pkg_name}"

    mkdir -p "${build_dir}/src" "${build_dir}/build" "${build_dir}/install"
    log_info "构建目录: ${build_dir}"
    echo "$build_dir"
}

# ── 记录到回传清单 ──────────────────────────────────────────────────────────
# 用法: record_handoff <包名> <编译器> <版本> <编译命令> <安装路径> <构建脚本>
record_handoff() {
    local name="$1" compiler="$2" version="$3"
    local cmd="$4" prefix="$5" build_sh="$6"
    echo "| ${name} | ${compiler} | ${version} | ${cmd} | ${prefix} | ${build_sh} |" >> "$HANDOFF_OUT"
    log_info "已回传: ${name} ${compiler} → $HANDOFF_OUT"
}

# ── 记录到日志 ──────────────────────────────────────────────────────────────
# 用法: record_log <包名> <编译器> <版本> <状态> <重试次数> <命令摘要> <备注>
record_log() {
    local name="$1" compiler="$2" version="$3" status="$4"
    local retries="$5" cmd_summary="$6" note="$7"
    echo "| ${name} | ${compiler} | ${version} | ${status} | ${retries} | ${cmd_summary} | ${note} |" >> "$LOG_FILE"
}

# ── 保存构建脚本 ────────────────────────────────────────────────────────────
# 用法: save_build_sh <包名> <内容>
save_build_sh() {
    local pkg_name="$1"
    local content="$2"
    local build_sh="${SPACK_WORKFLOW_DIR}/manual-build/${pkg_name}/build.sh"
    echo "$content" > "$build_sh"
    chmod +x "$build_sh"
    log_info "构建脚本已保存: ${build_sh}"
    echo "$build_sh"
}

# ── 解析移交清单并输出待处理列表 ─────────────────────────────────────────────
FILTER="${1:-all}"

log_step "移交清单内容:"
cat "$HANDOFF_IN"
echo ""

# 输出待处理包列表（供 AI Agent 参考）
log_step "待手动编译的包:"
while IFS='|' read -r _ name compiler version spec fail_reason source_url pkg_path _; do
    # 跳过表头和分隔线
    name=$(echo "$name" | xargs)  # trim
    [[ -z "$name" || "$name" == "包名" || "$name" == *---* ]] && continue

    if [ "$FILTER" != "all" ] && [ "$FILTER" != "$name" ]; then
        continue
    fi

    compiler=$(echo "$compiler" | xargs)
    version=$(echo "$version" | xargs)
    spec=$(echo "$spec" | xargs)
    fail_reason=$(echo "$fail_reason" | xargs)
    source_url=$(echo "$source_url" | xargs)

    log_info "包: ${name} | 编译器: ${compiler} | 版本: ${version} | 失败原因: ${fail_reason}"

    # 创建构建目录
    # create_build_dir 先 log_info 再 echo 路径，而 log_info 也是 echo 到 stdout →
    # 直接捕获会拿到两行（含 "[INFO] …" 前缀），污染后面打印的构建目录/回传命令
    build_dir=$(create_build_dir "$name" | tail -1)

    # 加载 HPCKit 环境
    if ! load_hpckit_env "$compiler"; then
        log_error "HPCKit 环境加载失败，跳过 ${name}"
        record_log "$name" "$compiler" "$version" "❌ 失败" 0 "—" "HPCKit环境加载失败"
        continue
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  包名: ${name}"
    echo "  编译器: ${compiler}"
    echo "  版本: ${version}"
    echo "  失败原因: ${fail_reason}"
    echo "  源码URL: ${source_url}"
    echo "  构建目录: ${build_dir}"
    echo "  安装前缀: ${build_dir}/install"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "请 AI Agent 参照 AI_INSTRUCTION.md 执行手动编译。"
    echo "成功后使用以下函数回传编译命令："
    echo "  record_handoff \"${name}\" \"${compiler}\" \"${version}\" \"<编译命令>\" \"${build_dir}/install\" \"${build_dir}/build.sh\""
    echo "  record_log \"${name}\" \"${compiler}\" \"${version}\" \"✅ 成功\" <重试次数> \"<命令摘要>\" \"<备注>\""
    echo "  save_build_sh \"${name}\" \"<构建脚本内容>\""
    echo ""

done < "$HANDOFF_IN"

echo ""
log_step "=== 阶段 3.5 初始化完成 ==="
log_info "回传清单: $HANDOFF_OUT"
log_info "编译日志: $LOG_FILE"
log_info ""
log_info "AI Agent 请参照 AI_INSTRUCTION.md 逐个包执行手动编译。"
log_info "完成后回到阶段3，执行: bash stage3-install/install_batch.sh --from-3.5"
