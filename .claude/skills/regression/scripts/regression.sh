#!/usr/bin/env bash
# regression.sh — run a set of testbenches and print a pass/fail matrix.
#
# Usage:
#   regression.sh <pattern|all> [MODE]      run matching listfiles (MODE default: run)
#   regression.sh <pattern|all> --count     just list matches, don't run
#
# <pattern> is a case-insensitive regex over listfile basenames; `all` = everything.
# Exit: 0 if every run is PASS, else 1.
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || { echo "ERROR: cannot cd to project root"; exit 2; }

RUN_TB=".claude/skills/sim-run/scripts/run_tb.sh"
[ -x "$RUN_TB" ] || { echo "ERROR: sim-run helper not found/executable: $RUN_TB"; exit 2; }

sel="${1:-}"
[ -z "$sel" ] && { echo "usage: regression.sh <pattern|all> [MODE|--count]"; exit 2; }
arg2="${2:-run}"

all_configs() { ls sim/listfiles/*.f 2>/dev/null | xargs -n1 basename | sed 's/\.f$//'; }

if [ "$sel" = "all" ]; then
  configs="$(all_configs)"
else
  configs="$(all_configs | grep -iE "$sel" || true)"
fi

if [ -z "$configs" ]; then
  echo "No listfiles match '$sel'."; exit 2
fi

count="$(printf '%s\n' "$configs" | grep -c .)"

if [ "$arg2" = "--count" ]; then
  echo "$count listfile(s) match '$sel':"
  printf '%s\n' "$configs" | sed 's/^/  /'
  exit 0
fi

MODE="$arg2"
echo "Running $count testbench(es) [MODE=$MODE]..."
echo "================================================================"

pass=0; fail=0; err=0; unk=0
declare -a rows
while IFS= read -r c; do
  [ -z "$c" ] && continue
  out="$("$RUN_TB" "$c" "" "$MODE" 2>&1)"
  vline="$(printf '%s\n' "$out" | grep -E '^VERDICT:' | tail -1)"
  v="$(printf '%s' "$vline" | sed -E 's/^VERDICT: *([A-Z/ ()a-z]+).*/\1/' | awk '{$1=$1;print}')"
  log="$(printf '%s' "$vline" | grep -oE 'log: [^)]*' | cut -d' ' -f2)"
  case "$v" in
    PASS*)               pass=$((pass+1)); tag="PASS " ;;
    COMPILE*|*ERROR*)    err=$((err+1));   tag="ERROR" ;;
    FAIL*)               fail=$((fail+1)); tag="FAIL " ;;
    *)                   unk=$((unk+1));   tag="UNK  " ;;
  esac
  reason=""
  if [ "$tag" != "PASS " ]; then
    reason="$(printf '%s\n' "$out" | grep -iE '\[FAIL\]|<-- *FAIL|\*\* Error|mismatch|timeout' | head -1 | awk '{$1=$1;print}')"
  fi
  printf '  [%s] %-40s %s\n' "$tag" "$c" "$reason"
  rows+=("$tag|$c|$log|$reason")
done <<EOF
$configs
EOF

echo "================================================================"
echo "TALLY: PASS $pass / FAIL $fail / ERROR $err / UNKNOWN $unk   (of $count)"
if [ $((fail+err+unk)) -gt 0 ]; then
  echo "Non-PASS logs:"
  for r in "${rows[@]}"; do
    case "$r" in PASS*) continue;; esac
    IFS='|' read -r tag c log reason <<< "$r"
    printf '  %-40s %s\n' "$c" "$log"
  done
  exit 1
fi
echo "ALL PASS"
exit 0
