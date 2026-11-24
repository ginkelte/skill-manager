#!/usr/bin/env bash
# pii-scan.sh — publication gate: looks for forbidden aliases/identifiers in a
# directory and, if it is a git repo, also in its history, authors and remote.
#
# Usage:
#   pii-scan.sh <dir>                    # tree + history
#   pii-scan.sh <dir> --tree-only        # working tree only
#   pii-scan.sh <dir> --terms <file>     # alternative term list
#   pii-scan.sh --show-terms             # print the active list and exit
#
# The default list does NOT live inside the skill: if the terms were here,
# the skill itself would be the leak. Default: <root>/../references/pii-blocklist.txt
# (one term per line, `#` comments), with <root> derived from this script's
# location. Override with $PII_BLOCKLIST.
#
# Exit codes: 0 = clean · 1 = hits found · 2 = usage/input error.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../../.." 2>/dev/null && pwd || echo "$SELF_DIR")"
# First candidate that exists wins; set $PII_BLOCKLIST to be explicit.
LIST=""
for c in "${PII_BLOCKLIST:-}" "$ROOT/../references/pii-blocklist.txt" "$SELF_DIR/../references/pii-blocklist.txt"; do
  [ -n "$c" ] && [ -f "$c" ] && { LIST="$c"; break; }
done
LIST="${LIST:-${PII_BLOCKLIST:-$ROOT/../references/pii-blocklist.txt}}"
DIR=""
TREE_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --show-terms) [ -f "$LIST" ] && sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$LIST" || \
                    { echo "pii-scan: no term list — set PII_BLOCKLIST or create <root>/../references/pii-blocklist.txt" >&2; exit 2; }
                  exit 0 ;;
    --tree-only)  TREE_ONLY=1; shift ;;
    --terms)      [ $# -ge 2 ] || { echo "pii-scan: --terms requires a file" >&2; exit 2; }; LIST="$2"; shift 2 ;;
    -h|--help)    sed -n '2,19p' "$0"; exit 0 ;;
    -*)           echo "pii-scan: unknown flag: $1" >&2; exit 2 ;;
    *)            DIR="${1%/}"; shift ;;
  esac
done

[ -n "$DIR" ] || { echo "pii-scan: missing directory to scan" >&2; exit 2; }
[ -d "$DIR" ] || { echo "pii-scan: $DIR does not exist" >&2; exit 2; }
[ -f "$LIST" ] || { echo "pii-scan: missing term list: $LIST — set PII_BLOCKLIST or create <root>/../references/pii-blocklist.txt" >&2; exit 2; }

PAT="$(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$LIST" | sed 's/[.[\*^$()+?{}|]/\\&/g' | paste -sd'|' -)"
[ -n "$PAT" ] || { echo "pii-scan: list $LIST is empty" >&2; exit 2; }

hits=0
echo "== list: $LIST =="
echo "== terms: $(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$LIST" | paste -sd' ' -) =="

echo
echo "-- tree ($DIR) --"
tree_hits="$(grep -rInE --exclude-dir=.git "$PAT" "$DIR" 2>/dev/null || true)"
if [ -n "$tree_hits" ]; then
  printf '%s\n' "$tree_hits" | sed "s|^$DIR/||" | head -40
  n="$(printf '%s\n' "$tree_hits" | wc -l)"; hits=$((hits + n))
  echo "-> $n hit(s) in the tree"
else
  echo "-> 0 hits"
fi

if [ "$TREE_ONLY" -eq 0 ] && [ -d "$DIR/.git" ]; then
  echo
  echo "-- history (commits, authors, diffs) --"
  hist="$(git -C "$DIR" log --all -p --format='COMMIT %h | %an <%ae> | %cn <%ce>' 2>/dev/null | grep -inE "$PAT" || true)"
  if [ -n "$hist" ]; then
    printf '%s\n' "$hist" | head -40
    n="$(printf '%s\n' "$hist" | wc -l)"; hits=$((hits + n))
    echo "-> $n hit(s) in the history (rewriting the tree does not fix it)"
  else
    echo "-> 0 hits"
  fi

  echo
  echo "-- remote owner --"
  rem="$(git -C "$DIR" remote -v 2>/dev/null | grep -iE "$PAT" || true)"
  if [ -n "$rem" ]; then
    printf '%s\n' "$rem"; hits=$((hits + 1)); echo "-> the handle appears in the remote URL"
  else
    echo "-> 0 hits"
  fi

  echo
  echo "-- PR refs --"
  refs="$(git -C "$DIR" ls-remote origin 'refs/pull/*/head' 2>/dev/null | wc -l)"
  if [ "$refs" -gt 0 ]; then
    echo "-> $refs visible PR ref(s): if any contains forbidden terms, only a new repo purges it"
  else
    echo "-> 0 refs"
  fi
fi

echo
if [ "$hits" -gt 0 ]; then
  echo "RESULT: NOT CLEAN — $hits hit(s). Redact before publishing."
  exit 1
fi
echo "RESULT: clean (0 hits)."
