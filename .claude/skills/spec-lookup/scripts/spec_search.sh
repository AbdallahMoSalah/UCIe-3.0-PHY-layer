#!/usr/bin/env bash
# spec_search.sh — page-aware keyword search over the UCIe spec PDF.
#
# Usage: spec_search.sh "<pattern>" [context_lines]
#   <pattern>      : case-insensitive regex
#   context_lines  : lines of context around each hit (default 3)
#
# Caches the extracted text under /tmp keyed by the PDF mtime.
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || { echo "ERROR: cannot cd to project root"; exit 2; }

command -v pdftotext >/dev/null 2>&1 || { echo "ERROR: pdftotext not installed"; exit 2; }

PAT="${1:-}"
[ -z "$PAT" ] && { echo 'usage: spec_search.sh "<pattern>" [context_lines]'; exit 2; }
CTX="${2:-3}"

# locate the spec PDF (first *.pdf under docs/Spec)
PDF="$(find docs/Spec -maxdepth 1 -name '*.pdf' 2>/dev/null | head -1)"
[ -z "$PDF" ] && { echo "ERROR: no PDF found under docs/Spec"; exit 2; }

# cache extraction keyed by mtime
mt="$(stat -c %Y "$PDF" 2>/dev/null || stat -f %m "$PDF" 2>/dev/null)"
CACHE="/tmp/ucie_spec_${mt}.txt"
if [ ! -s "$CACHE" ]; then
  echo "(extracting text once -> $CACHE)" >&2
  pdftotext "$PDF" "$CACHE" 2>/dev/null || { echo "ERROR: pdftotext failed"; exit 2; }
fi

# page-aware search: records are form-feed-separated pages; NR = page number.
# Case-insensitive via tolower() on both sides (portable across POSIX awk).
awk -v pat="$PAT" -v ctx="$CTX" '
  BEGIN { RS="\f"; lpat=tolower(pat); hits=0 }
  {
    n=split($0, L, "\n")
    for (i=1;i<=n;i++) {
      if (tolower(L[i]) ~ lpat) {
        hits++
        print "── page " NR " ──"
        lo=(i-ctx<1?1:i-ctx); hi=(i+ctx>n?n:i+ctx)
        for (j=lo;j<=hi;j++) {
          line=L[j]; gsub(/[ \t]+$/,"",line)
          if (line != "") print "  " line
        }
        print ""
      }
    }
  }
  END {
    if (hits==0) print "No matches for /" pat "/i in " FILENAME
    else print "(" hits " hit(s))"
  }
' FILENAME="$PDF" "$CACHE"
