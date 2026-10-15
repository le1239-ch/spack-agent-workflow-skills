#!/bin/bash
#===============================================================================
# 全流程串联脚本 — 依次执行阶段1~5
# 用法：bash run_all.sh [--skip-install] [--skip-optimize]
#       --skip-install    跳过阶段 3 / 3.5 / 4（只做阶段 1/2/5）
#       --skip-optimize   只跳过阶段 4（编译期优化）
#       bash run_all.sh   完整流程
#
# ⚠ 本脚本是 batch 模式：阶段 3/3.5 的设计是「由 AI Agent 按各自 AI_INSTRUCTION.md
#   的决策树逐步执行」，直接跑本脚本会用批处理脚本替代 Agent 决策（见
#   stage3-install/AI_INSTRUCTION.md「执行方式」）。正式交付建议逐阶段按指令执行。
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WF_ROOT="$(dirname "$SCRIPT_DIR")"
source "${SCRIPT_DIR}/lib_common.sh"

SKIP_INSTALL=false
SKIP_OPTIMIZE=false
for _arg in "$@"; do
    case "$_arg" in
        --skip-install)  SKIP_INSTALL=true ;;
        --skip-optimize) SKIP_OPTIMIZE=true ;;
        *) log_warn "未知参数: ${_arg}（支持 --skip-install / --skip-optimize）" ;;
    esac
done

log_step "========================================"
log_step "鲲鹏920F + Spack + BiSheng + KML"
log_step "HPC 软件 Agent Workflow 全流程"
log_step "========================================"

# ── 阶段 1 ─────────────────────────────────────────────────────────────────
log_step ">>> 阶段 1: 环境盘点 + Spack 安装 + 鲲鹏 repo 配置 + HPCKit 安装"
bash "${WF_ROOT}/stage1-setup-spack/setup_spack.sh" || { log_error "阶段1失败"; exit 1; }

if ! grep -q "target=aarch64.*✅" "${WF_ROOT}/stage1-setup-spack/env_report.md" 2>/dev/null; then
    log_warn "阶段1通过条件未满足（aarch64 未确认），但继续执行"
fi

# ── 阶段 2 ─────────────────────────────────────────────────────────────────
log_step ">>> 阶段 2: 待安装软件清单（需用户手动填写）"
if [ ! -f "${WF_ROOT}/stage2-packages/packages_to_install.yaml" ]; then
    log_error "packages_to_install.yaml 不存在，请手动填写"
    exit 1
fi
log_info "待安装清单: ${WF_ROOT}/stage2-packages/packages_to_install.yaml"
log_info "请确认已填写软件清单后按回车继续..."
read -r || true

# ── 阶段 3 ~ 3.5（--skip-install 时整体跳过，因为两者都会真的编译/安装）────
if [ "$SKIP_INSTALL" = "true" ]; then
    log_warn ">>> 跳过阶段 3 / 3.5 / 4（--skip-install）"
else

# ── 阶段 3 ─────────────────────────────────────────────────────────────────
log_step ">>> 阶段 3: 安装软件（路径A/A2/B，3次重试 → 失败转3.5）"
log_warn "batch 模式：正常流程应由 AI Agent 按 stage3-install/AI_INSTRUCTION.md 的决策树逐步执行"
bash "${WF_ROOT}/stage3-install/install_batch.sh" || log_warn "阶段3有失败，继续"

# ── 阶段 3.5（如有移交清单） ────────────────────────────────────────────────
HANDOFF_35="${WF_ROOT}/stage3-install/handoff_to_3.5.md"
if [ -f "$HANDOFF_35" ]; then
    # 用 awk 计数（grep|grep|wc 在 pipefail 下遇到空表会返回非 0，赋值失败即中止脚本）
    handoff_count=$(awk -F'|' '/^[[:space:]]*\|/ && $2 !~ /包名/ && $2 !~ /^[[:space:]]*-+[[:space:]]*$/ {c++} END{print c+0}' "$HANDOFF_35")
    if [ "$handoff_count" -gt 0 ]; then
        log_step ">>> 阶段 3.5: 手动编译兜底（${handoff_count} 个包移交）"
        bash "${WF_ROOT}/stage3.5-manual-build/manual_build.sh" || log_warn "阶段3.5有失败，继续"

        # stage3.5 手动编译成功后，回传编译命令给 stage3 路径C
        HANDOFF_BACK="${WF_ROOT}/stage3.5-manual-build/handoff_to_3.md"
        if [ -f "$HANDOFF_BACK" ]; then
            back_count=$(awk -F'|' '/^[[:space:]]*\|/ && $2 !~ /包名/ && $2 !~ /^[[:space:]]*-+[[:space:]]*$/ {c++} END{print c+0}' "$HANDOFF_BACK")
            if [ "$back_count" -gt 0 ]; then
                log_step ">>> 阶段 3 路径C: 据手动编译命令写 package.py（${back_count} 个包）"
                bash "${WF_ROOT}/stage3-install/install_batch.sh" --from-3.5 || log_warn "阶段3路径C有失败，继续"
            fi
        fi
    fi
fi

fi  # ← 结束 --skip-install 守卫（阶段 3 ~ 3.5）

# ── 阶段 4 ─────────────────────────────────────────────────────────────────
if [ "$SKIP_INSTALL" = "false" ] && [ "$SKIP_OPTIMIZE" = "false" ]; then
    log_step ">>> 阶段 4: 编译期优化"
    bash "${WF_ROOT}/stage4-compile-opt/compile_opt.sh" || log_warn "阶段4有失败，继续"
fi

# ── 阶段 5 ─────────────────────────────────────────────────────────────────
log_step ">>> 阶段 5: 交付 — 生成软件说明文档"
bash "${WF_ROOT}/stage5-deliver/deliver.sh" || log_warn "阶段5有失败，继续"

log_step "========================================"
log_step "全流程完成！"
log_step "========================================"
echo ""
echo "交付物清单:"
echo "  环境报告:   ${WF_ROOT}/stage1-setup-spack/env_report.md"
echo "  Spack配置:  ${WF_ROOT}/stage1-setup-spack/{packages,compilers,repos}.yaml"
echo "  待装清单:   ${WF_ROOT}/stage2-packages/packages_to_install.yaml"
echo "  安装日志:   ${WF_ROOT}/stage3-install/install_log.md"
echo "  移交清单:   ${WF_ROOT}/stage3-install/handoff_to_3.5.md (如有)"
echo "  手编日志:   ${WF_ROOT}/stage3.5-manual-build/manual_build_log.md (如有)"
echo "  回传清单:   ${WF_ROOT}/stage3.5-manual-build/handoff_to_3.md (如有)"
echo "  优化日志:   ${WF_ROOT}/stage4-compile-opt/compile_opt_log.md"
echo "  软件文档:   ${WF_ROOT}/stage5-deliver/<软件名>.md"
