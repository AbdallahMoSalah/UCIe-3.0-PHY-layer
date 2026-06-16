#!/usr/bin/env bash
# run_tb.sh — resolve TOP, run one QuestaSim testbench, print a concise verdict.
#
# Usage: run_tb.sh <CONFIG> [TOP] [MODE]
#   CONFIG : listfile basename (with or without .f), e.g. integration_tx_deser
#   TOP    : tb module name (optional — auto-resolved from listfile if omitted)
#   MODE   : run (default) | debug | report | ci
#
# Exit: 0 = PASS, 1 = FAIL/UNKNOWN, 2 = usage/resolution error.
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || { echo "ERROR: cannot cd to project root"; exit 2; }

CONFIG="${1:-}"
[ -z "$CONFIG" ] && { echo "usage: run_tb.sh <CONFIG> [TOP] [MODE]"; exit 2; }
TOP="${2:-}"
MODE="${3:-run}"

CONFIG="${CONFIG%.f}"                 # tolerate a trailing .f
CONFIG="$(basename "$CONFIG")"        # tolerate a full path
LF="sim/listfiles/${CONFIG}.f"

if [ ! -f "$LF" ]; then
  echo "ERROR: listfile not found: $LF"
  echo "Closest matches:"
  ls sim/listfiles/ 2>/dev/null | sed 's/\.f$//' | grep -iF "$CONFIG" | sed 's/^/  /' | head
  exit 2
fi

# --- gather the .sv files the listfile compiles (strip comments/blank/options) ---
# Emits one path per line, quotes stripped, options dropped. Handles paths with spaces.
listed_files() {
  while IFS= read -r line; do
    line="${line%%#*}"
    p="$(printf '%s' "$line" | awk '{$1=$1;print}')"
    p="${p%\"}"; p="${p#\"}"; p="${p%\'}"; p="${p#\'}"
    [ -z "$p" ] && continue
    case "$p" in [+-]*) continue;; esac
    printf '%s\n' "$p"
  done < "$LF"
}

# --- resolve TOP ----------------------------------------------------------------
if [ -z "$TOP" ]; then
  TOP="$(grep -oE 'TOP=[A-Za-z0-9_]+' "$LF" | head -1 | cut -d= -f2)"
fi
if [ -z "$TOP" ]; then
  # scan listed files for a module whose name looks like a testbench
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    m="$(grep -oiE '^\s*module\s+[A-Za-z0-9_]*tb[A-Za-z0-9_]*' "$f" \
          | awk '{print $2}' | head -1)"
    [ -n "$m" ] && TOP="$m"          # keep last tb-like module found
  done <<EOF
$(listed_files)
EOF
fi
if [ -z "$TOP" ]; then
  echo "ERROR: could not resolve TOP for '$CONFIG'. Re-run with it explicitly:"
  echo "  run_tb.sh $CONFIG <tb_module>"
  echo "Module candidates in this listfile:"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -oE '^\s*module\s+[A-Za-z0-9_]+' "$f" | awk '{print "  "$2}'
  done <<EOF
$(listed_files)
EOF
  exit 2
fi

echo ">>> CONFIG=$CONFIG  TOP=$TOP  MODE=$MODE"
LOG="$(mktemp -t simrun.XXXXXX.log)"
make "$MODE" CONFIG="$CONFIG" TOP="$TOP" 2>&1 | tee "$LOG"

# --- verdict --------------------------------------------------------------------
echo "================================================================"
echo "SUMMARY for CONFIG=$CONFIG TOP=$TOP"
grep -hiE '>>>|RESULT:|SUMMARY|scenarios_(pass|fail)|[0-9]+ *(passed|failed)|\bpass=|\bfail=|[0-9]+/[0-9]+ *(PASS|words|descrambled)' "$LOG" \
  | sed 's/^# //' | sort -u | sed 's/^/  /'

verdict="UNKNOWN"; rc=1
if grep -qE '\*\* Error|Compilation Failed|Error loading|cannot find|No such file' "$LOG"; then
  verdict="COMPILE/ELAB ERROR"; rc=2
elif grep -qiE '\[WATCHDOG\] *timeout' "$LOG"; then
  verdict="FAIL (watchdog timeout)"; rc=1
elif grep -qiE '>>> *(FAIL|SOME TESTS FAILED|FAILURES DETECTED|ABORT)|RESULT: *FAIL|>>> *FAIL' "$LOG"; then
  verdict="FAIL"; rc=1
elif grep -qiE 'fail(s|ed|=)? *[1-9]|[1-9][0-9]* *(failed|mismatch)' "$LOG"; then
  verdict="FAIL"; rc=1
elif grep -qiE '>>> *(PASS|ALL TESTS PASSED)|RESULT: *PASS' "$LOG"; then
  verdict="PASS"; rc=0
elif grep -qiE 'fail(s|ed|=)? *0\b' "$LOG" && grep -qiE '\[PASS\]|pass(ed)?' "$LOG"; then
  verdict="PASS"; rc=0
fi

if [ "$rc" -ne 0 ]; then
  echo "---- failing excerpts (last) ----"
  grep -niE '\[FAIL\]|<-- *FAIL|\*\* Error|mismatch|RESULT: *FAIL|timeout' "$LOG" \
    | tail -20 | sed 's/^/  /'
fi

echo "----------------------------------------------------------------"
echo "VERDICT: $verdict   (log: $LOG)"
exit "$rc"
