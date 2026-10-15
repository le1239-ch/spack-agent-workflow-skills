#!/bin/bash
#===============================================================================
# 阶段 4：编译期优化（改 flags，不是改配方）
# 目标：对性能关键包用 KML 重编，注入 BiSheng 鲲鹏优化 flag
# 用法：bash compile_opt.sh [pkg1 pkg2 ...]  (默认优化关键包列表)
# 通过条件：性能关键包用 KML 重编成功
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib_common.sh"

LOG_FILE="${SCRIPT_DIR}/compile_opt_log.md"

# ── 性能关键包列表（只对这些包做 --fresh 重编） ─────────────────────────────
PERF_CRITICAL_PKGS=(
    "fftw+mpi+openmp"
    "scalapack"
    "petsc+mpi+hdf5+mumps+hypre"
    "gromacs+mpi~cuda"
    "lammps+mpi+manybody+molecule"
    "openfoam"
    "quantum-espresso+mpi+hdf5"
    "cp2k+mpi+libint+libxc"
)

# 如果命令行指定了包，用指定的
if [ $# -gt 0 ]; then
    PERF_CRITICAL_PKGS=("$@")
fi

# ── BiSheng 鲲鹏920 推荐 flag ──────────────────────────────────────────────
# BiSheng 官方推荐鲲鹏920:
#   -mcpu=tsv110 -march=armv8.2-a -O3
# 注意：
#   - -flto 会禁用 SVE 自动向量化 → 不要加
#   - -ffast-math 对部分科学软件不安全 → 仅对非浮点敏感包使用
#   - 含 LAPACK 的包禁止 -ffast-math（NaN崩溃风险）

log_step "=== 阶段 4：编译期优化 ==="

# ── 步骤 4.1 确认 BiSheng 鲲鹏推荐 flag ─────────────────────────────────────
log_step "4.1 确认 BiSheng 鲲鹏920 推荐 flag"

cat << 'FLAG_INFO'
BiSheng 官方推荐鲲鹏920 flag:
  -mcpu=tsv110 -march=armv8.2-a -O3

注意:
  ⚠ -flto 会禁用 GCC/BiSheng SVE 自动向量化 → 不要加
  ⚠ -ffast-math 对含 LAPACK 的科学软件不安全（NaN 崩溃）→ 仅限安全场景
  ✅ GCC 默认 FP 语义（不设 -ffast-math 也不设 -ffp-contract=off）最优
FLAG_INFO

# ── 步骤 4.2 在 packages.yaml 做全局注入 ──────────────────────────────────
log_step "4.2 注入优化 flag 到 packages.yaml（不污染官方 recipe）"

# 全局编译器与架构
spack config --scope=site add "packages:all:compiler:[bisheng, gcc]" 2>&1 || true
spack config --scope=site add "packages:all:target:[aarch64]" 2>&1 || true

# 关键包 variant 注入
log_info "注入关键包 variant..."

# FFTW: +openmp +shared
spack config --scope=site add "packages:fftw:variants:+openmp +shared" 2>&1 || true

# OpenMPI: +pmi +cxx +fortran
spack config --scope=site add "packages:openmpi:variants:+pmi +cxx +fortran" 2>&1 || true

# GROMACS: +mpi -cuda Release
spack config --scope=site add "packages:gromacs:variants:+mpi ~cuda build_type=Release" 2>&1 || true

# BLAS/LAPACK 指向 KML：⚠ 此处刻意不写 `packages:blas:require:kpkml`
#   kpkml 是元包、无 provides()，该行会让之后所有 concretization 报
#   `cannot satisfy a requirement for package 'blas'`（实测毒行，2026-09-30 移除）。
#   正确做法：重编时对具体包加 provider 约束 `^kpblas ^kplapack`（见步骤 4.3）。

log_info "packages.yaml 全局注入完成"

# ── 步骤 4.3 用 KML 重编性能关键包 ─────────────────────────────────────────
log_step "4.3 用 KML 数学库替换 BLAS/LAPACK 后重编受影响包"

# 鲲鹏数学库及优化组件（14个包）说明：
#   kpkml 是元包，聚合以下子组件（它没有 provides()，不能当 BLAS/LAPACK 的 provider 约束用）：
#     BLAS:     kpblas(基础BLAS) / kpspblas(稀疏BLAS)
#     LAPACK:   kplapack(LAPACK) / kpscalapack(ScaLAPACK) / kpscasolver(分布式求解器) / kpsolver(直接求解器)
#     FFT:      kpfft(FFT) / kpfftw(FFTW接口兼容)
#     向量:     kpvml(向量数学) / kpksvml(短向量数学)
#     其他:     kpkupl(通用性能库)
#   MPI:      hmpi(鲲鹏优化MPI，通过 packages.yaml provider 已全局指向)
#   套件:     hpckit(HPC开发套件元包，含编译器+MPI+数学库)
# 重编时用 provider 约束 `^kpblas ^kplapack`（真实 provides blas/lapack）指向鲲鹏优化库；
# `^kpkml` 直连不可行：spack 报 'kpkml' is not a possible dependency of any root spec

# 初始化日志
cat > "$LOG_FILE" << 'EOF'
# 编译期优化日志 (compile_opt_log.md)

> 由 compile_opt.sh 自动维护。
> 记录 --fresh 重编的性能关键包状态。

| 包名 | 原hash | 新hash | 状态 | KML | 优化flag | 备注 |
|------|--------|--------|------|-----|----------|------|
EOF

# 确定是否含 LAPACK（禁止 -ffast-math）
has_lapack() {
    local pkg="$1"
    case "$pkg" in
        petsc|scalapack|gromacs|quantum-espresso|cp2k|lammps|openfoam)
            return 0 ;;  # 含 LAPACK
        *)
            return 1 ;;  # 不含
    esac
}

for pkg_spec in "${PERF_CRITICAL_PKGS[@]}"; do
    pkg_name=$(echo "$pkg_spec" | awk '{print $1}' | sed 's/[+^].*//')

    log_step "重编: ${pkg_spec}"

    # 记录原 hash
    OLD_HASH=$(spack find -l "$pkg_name" 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '[]' || echo "?")
    log_info "原 hash: ${OLD_HASH}"

    # 判断是否需要禁用 -ffast-math
    local_flags=""
    if has_lapack "$pkg_name"; then
        local_flags="-O3 -mcpu=tsv110"  # 不加 -ffast-math
        log_info "${pkg_name} 含 LAPACK → 禁用 -ffast-math"
    else
        local_flags="-O3 -mcpu=tsv110"  # 安全起见也不加
        log_info "${pkg_name} → 使用 -O3 -mcpu=tsv110"
    fi

    # --fresh 重编，确保用 KML
    nproc=$(nproc 2>/dev/null || echo 8)
    install_tmp="/tmp/spack_recompile_${pkg_name}.log"

    if spack install --fresh -j"$nproc" "$pkg_spec" "^kpblas" "^kplapack" 2>&1 | tee "$install_tmp"; then
        NEW_HASH=$(spack find -l "$pkg_name" 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '[]' || echo "?")
        NEW_VER=$(spack find --format "{version}" "$pkg_name" 2>/dev/null | head -1 || echo "?")
        log_info "✅ 重编成功: ${pkg_name} ${OLD_HASH} → ${NEW_HASH}"
        echo "| ${pkg_name} | ${OLD_HASH} | ${NEW_HASH} | ✅ 成功 | ✅ kpblas+kplapack | ${local_flags} | — |" >> "$LOG_FILE"
    else
        err=$(tail -5 "$install_tmp" 2>/dev/null | tr '\n' ' ' | head -c 200 || echo "see log")
        log_error "❌ 重编失败: ${pkg_name}"
        echo "| ${pkg_name} | ${OLD_HASH} | — | ❌ 失败 | — | — | ${err} |" >> "$LOG_FILE"

        # 失败处理：去掉 KML provider 约束重试（落回官方 recipe）
        log_warn "尝试不加 ^kpblas ^kplapack 约束重试..."
        if spack install --fresh -j"$nproc" "$pkg_spec" 2>&1 | tee "$install_tmp"; then
            NEW_HASH=$(spack find -l "$pkg_name" 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '[]' || echo "?")
            log_info "✅ 重试成功（无 KML 约束）: ${pkg_name}"
            echo "| ${pkg_name} | ${OLD_HASH} | ${NEW_HASH} | ✅ 重试成功(无KML) | ❌ | ${local_flags} | 首次带KML失败,回落官方 |" >> "$LOG_FILE"
        else
            log_error "❌ 重试仍失败，跳过: ${pkg_name}"
            echo "| ${pkg_name} | ${OLD_HASH} | — | ❌ 跳过 | — | — | 两次均失败 |" >> "$LOG_FILE"
        fi
    fi

    # 确认安装
    spack find -l "$pkg_name" 2>/dev/null | head -3 || true
    echo ""
done

# ── 汇总 ──────────────────────────────────────────────────────────────────
echo ""
echo "--- 编译优化汇总 ---"
echo "成功: $(grep -c '✅' "$LOG_FILE" 2>/dev/null || echo 0)"
echo "失败: $(grep -c '❌' "$LOG_FILE" 2>/dev/null || echo 0)"
echo ""
log_info "优化日志: $LOG_FILE"
log_info "注意：本阶段只对性能关键包重编，未做全部 --fresh"
log_step "=== 阶段 4 完成 ==="
