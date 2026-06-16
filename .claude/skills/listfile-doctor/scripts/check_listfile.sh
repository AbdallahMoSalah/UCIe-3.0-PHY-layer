#!/usr/bin/env bash
# check_listfile.sh — verify every file path in a listfile exists; suggest fixes.
#
# Usage: check_listfile.sh <CONFIG|all>
#   CONFIG : listfile basename (with or without .f)
#   all    : check every sim/listfiles/*.f
#
# Exit: 0 = all checked listfiles clean, 1 = at least one missing path.
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || { echo "ERROR: cannot cd to project root"; exit 2; }

suggest() {                     # $1 = missing path -> print candidate locations
  local base; base="$(basename "$1")"
  local hits
  hits="$(git ls-files "*/$base" "$base" 2>/dev/null | sort -u | head -4)"
  [ -z "$hits" ] && hits="$(find rtl tb sim -name "$base" 2>/dev/null | sort -u | head -4)"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/      -> try: /'
  else
    echo "      -> no file named '$base' anywhere in repo (RTL may be missing)"
  fi
}

check_one() {                   # $1 = listfile path -> 0 clean / 1 has missing
  local lf="$1" bad=0 p
  echo "## $(basename "$lf")"
  while IFS= read -r line; do
    line="${line%%#*}"                       # strip inline comment
    p="$(printf '%s' "$line" | awk '{$1=$1;print}')"   # trim
    p="${p%\"}"; p="${p#\"}"                 # strip surrounding quotes (paths with spaces)
    p="${p%\'}"; p="${p#\'}"
    [ -z "$p" ] && continue
    case "$p" in [+-]*) continue;; esac      # skip vlog options
    if [ ! -f "$p" ]; then
      bad=1
      echo "  MISSING: $p"
      suggest "$p"
    fi
  done < "$lf"
  [ "$bad" -eq 0 ] && echo "  OK"
  return "$bad"
}

sel="${1:-}"
[ -z "$sel" ] && { echo "usage: check_listfile.sh <CONFIG|all>"; exit 2; }

rc=0
if [ "$sel" = "all" ]; then
  for lf in sim/listfiles/*.f; do
    check_one "$lf" || rc=1
  done
else
  sel="${sel%.f}"; sel="$(basename "$sel")"
  lf="sim/listfiles/${sel}.f"
  if [ ! -f "$lf" ]; then
    echo "ERROR: listfile not found: $lf"
    ls sim/listfiles/ | sed 's/\.f$//' | grep -iF "$sel" | sed 's/^/  did you mean: /' | head
    exit 2
  fi
  check_one "$lf" || rc=1
fi

echo "----------------------------------------------------------------"
[ "$rc" -eq 0 ] && echo "RESULT: all paths resolve" || echo "RESULT: missing paths found (see MISSING lines above)"
exit "$rc"
