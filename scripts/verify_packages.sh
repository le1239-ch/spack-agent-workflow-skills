#!/bin/bash
# ============================================================================
# Kunpeng Workflow — stage2 待安装清单验证探针
# ============================================================================
# 用途：按 stage2-packages/AI_INSTRUCTION.md 的口径验证 packages_to_install.yaml：
#         存在性 -> 指定版本可用性 -> spack spec（%gcc + %llvm） -> provider 路由
#       只读，不安装、不修改任何文件（stage2 禁止 spack install）。
#
# 用法：
#   bash scripts/verify_packages.sh [清单路径]
#   默认清单 /home/zhangyuhang/workflow/stage2-packages/packages_to_install.yaml
#
# 退出码：0 = 所有非注释条目全部 PASS；1 = 有 FAIL（阶段3 需按 AI_INSTRUCTION 处理）。
# ============================================================================
set -uo pipefail

LIST="${1:-/home/zhangyuhang/workflow/stage2-packages/packages_to_install.yaml}"
WORKFLOW=/home/zhangyuhang/workflow
PASS=0; FAIL=0

# --- 环境：裸 source，不带管道/重定向（管道会让 source 跑在子 shell，环境不落回） ---
# shellcheck disable=SC1091
source "$WORKFLOW/scripts/spack-env.sh" >/dev/null 2>&1 || {
  echo "FATAL: cannot source $WORKFLOW/scripts/spack-env.sh"; exit 1; }
command -v spack >/dev/null || { echo "FATAL: spack not on PATH after source"; exit 1; }

echo "清单: $LIST"
echo "spack: $(spack --version 2>/dev/null)  arch: $(uname -m)"
echo

# --- 版本提取：Safe versions 条目是 `VERSION[git]URL` 无空格拼接，
#     必须用前导版本号正则，不能按空白切分或整串比对（否则全判 NO） ---
ver_has() {  # $1=pkg $2=want
  spack info "$1" 2>/dev/null \
    | awk '/Safe versions:/{f=1;next} /^$/{if(f)f=0} f' \
    | tr ' ' '\n' | sed -n 's/^\([0-9][0-9a-zA-Z._-]*\).*/\1/p' \
    | grep -qx "$2" && echo YES || echo NO
}

spec_check() {  # $1=pkg $2=ver $3=compiler -> 0/1，输出已解析根 spec 或错误摘要
  local out rc
  out=$(spack spec "$1@$2 %$3" 2>&1); rc=$?
  if [ $rc -ne 0 ]; then
    echo "FAIL   spec $1@$2 %$3  RC=$rc"
    printf '%s\n' "$out" | grep -iE 'only available|conflict|no version|cannot satisfy' | head -2 | sed 's/^/         /'
  else
    echo "PASS   spec $1@$2 %$3   -> $(printf '%s\n' "$out" | grep -E '^\s*-?\s*[a-z0-9_.+-]+@' | head -1 | sed 's/^ *-* *//;s/ .*%/%/')"
  fi
  return $rc
}

# --- 主循环：只处理非注释、非空行 ---
while IFS= read -r raw; do
  line="$(printf '%s' "$raw" | sed 's/#.*$//' | tr -d '\r' | sed 's/^ *//;s/ *$//')"
  [ -z "$line" ] && continue
  IFS=',' read -r pkg want comp _ <<<"$line"
  pkg="$(printf '%s' "$pkg" | tr -d ' ')"; want="$(printf '%s' "$want" | tr -d ' ')"; comp="$(printf '%s' "$comp" | tr -d ' ')"
  echo "===== $pkg  (version='$want' compiler='$comp')"

  loc=$(spack location -p "$pkg" 2>/dev/null)
  if [ -z "$loc" ]; then
    echo "FAIL   exists: NO  (spack location -p 无输出)"
    FAIL=$((FAIL+1)); continue
  fi
  echo "PASS   exists: YES -> $loc"

  if [ -n "$want" ]; then
    v=$(ver_has "$pkg" "$want")
    if [ "$v" = YES ]; then echo "PASS   version $want in Safe versions"
    else echo "FAIL   version $want NOT in Safe versions"; fi
    [ "$v" = YES ] || FAIL=$((FAIL+1))
    sstr="$pkg@$want"
  else
    sstr="$pkg"
  fi

  case "$comp" in
    gcc)     clist="gcc" ;;
    bisheng|llvm) clist="llvm" ;;
    "")      clist="gcc llvm" ;;   # 空 = spack 默认两版本，按 gcc+llvm 各验一次
    both|*)  clist="gcc llvm" ;;
  esac

  for c in $clist; do
    out=$(spack spec "$sstr %$c" 2>&1); rc=$?
    if [ $rc -ne 0 ]; then
      FAIL=$((FAIL+1))
      echo "FAIL   spec $sstr %$c  RC=$rc"
      printf '%s\n' "$out" | grep -iE 'only available|conflict|no version|cannot satisfy' | head -2 | sed 's/^/         /'
    else
      PASS=$((PASS+1))
      root=$(printf '%s\n' "$out" | grep -E '^\s*-?\s*[a-z0-9_.+-]+@' | head -1 | sed 's/^ *-* *//')
      echo "PASS   spec $sstr %$c"
      echo "         root: $root"
      # 提示：填写的版本范围可能被解析成同前缀的更高版本（@5.3 -> @5.3.1）
      got=$(printf '%s' "$root" | sed -n "s/^$pkg@\([^ ]*\).*/\1/p")
      [ -n "$want" ] && [ -n "$got" ] && [ "$got" != "$want" ] && \
        echo "         NOTE: 填写 '$want' 实际解析为 '$got'（@X.Y 是版本范围；精确锁定用 @=$want）"
      # provider 路由：确认走鲲鹏组件而非回落系统库
      printf '%s\n' "$out" | grep -oE '(kpblas|kplapack|kpfftw|hmpi|openblas|openmpi|mpich|netcdf-c|hdf5)@[0-9][^ ]*' \
        | sort -u | sed 's/^/         dep: /'
    fi
  done
  echo
done < "$LIST"

echo "============================================"
echo "TOTAL  pass=$PASS  fail=$FAIL"
[ "$FAIL" -eq 0 ] && echo "结论：清单全部条目可解析，可直接进入阶段3。" \
                  || echo "结论：存在 FAIL 条目 -> 阶段3 按 AI_INSTRUCTION 走「自写 package.py / 手动编译」，不要在阶段2 改动清单。"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
