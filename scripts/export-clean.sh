#!/usr/bin/env bash
# export-clean.sh — copy a skill into an export directory applying the redaction
# map, and fail if any forbidden term survives.
#
# Usage:
#   export-clean.sh <skill-dir> <destination> [--force]
#
# - Copies SKILL.md, learnings.md, references/, templates/, scripts/.
# - Applies, line by line, the redaction map (LITERAL<TAB>REPLACEMENT).
# - Verifies with pii-scan.sh: if the tree still has hits, aborts and does NOT leave
#   the export looking ready (exit 1). History/owner are reviewed separately.
#
# Default paths (override with environment variables):
#   PII_EXPORT_MAP  <root>/../references/pii-export-map.txt
#   PII_BLOCKLIST   <root>/../references/pii-blocklist.txt
# <root> is derived from this script's own location (scripts/ -> skill -> category
# -> root), so no absolute path is baked in.
set -uo pipefail

SKILL_DIR="${1:-}"; DEST="${2:-}"; FORCE="${3:-}"
[ -n "$SKILL_DIR" ] && [ -n "$DEST" ] || { echo "export-clean: usage: export-clean.sh <skill-dir> <dest> [--force]" >&2; exit 1; }
SKILL_DIR="${SKILL_DIR%/}"; DEST="${DEST%/}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../../.." && pwd)"
MAP=""
for c in "${PII_EXPORT_MAP:-}" "$ROOT/../references/pii-export-map.txt" "$SELF_DIR/../references/pii-export-map.txt"; do
  [ -n "$c" ] && [ -f "$c" ] && { MAP="$c"; break; }
done
MAP="${MAP:-${PII_EXPORT_MAP:-$ROOT/../references/pii-export-map.txt}}"
SCAN="$(dirname "$0")/pii-scan.sh"

die() { printf 'export-clean: %s\n' "$1" >&2; exit 1; }

[ -n "${SKILL_DIR:-}" ] && [ -n "${DEST:-}" ] || die "usage: export-clean.sh <skill-dir> <destination> [--force]"
[ -d "$SKILL_DIR" ] || die "skill does not exist: $SKILL_DIR"
[ -f "$MAP" ] || die "missing redaction map: $MAP"
[ -x "$SCAN" ] || die "missing scripts/pii-scan.sh (or not executable)"

if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ] && [ "$FORCE" != "--force" ]; then
  die "$DEST is not empty (use --force to overwrite)"
fi

mkdir -p "$DEST"
rm -rf "${DEST:?}/SKILL.md" "${DEST:?}/learnings.md" "${DEST:?}/references" "${DEST:?}/templates" "${DEST:?}/scripts"
cp -a "$SKILL_DIR/SKILL.md" "$SKILL_DIR/learnings.md" "$DEST"/
for d in references templates scripts; do
  [ -d "$SKILL_DIR/$d" ] && cp -a "$SKILL_DIR/$d" "$DEST"/
done

# Apply the map: each LITERAL<TAB>REPLACEMENT line becomes a s|LITERAL|REPLACEMENT|g.
applied=0
while IFS=$'\t' read -r literal replacement; do
  case "$literal" in ''|'#'*) continue ;; esac
  [ -n "${replacement+x}" ] || replacement=""
  # escape sed delimiters
  # escaped: '|' delimiter included, otherwise a rule with pipes breaks sed
  lit_esc="$(printf '%s' "$literal" | sed 's/[][\/$*.^|]/\\&/g')"
  rep_esc="$(printf '%s' "$replacement" | sed 's/[][\/$*.^|]/\\&/g')"
  find "$DEST" -type f -print0 | xargs -0 -r sed -i "s|${lit_esc}|${rep_esc}|g" 2>/dev/null
  applied=$((applied + 1))
done < "$MAP"

# compiled caches never belong in an export
find "$DEST" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null

# Session knowledge never ships: the public copy of learnings.md keeps ONLY the canonical header
# (the append-only rules live there and are useful to a reader), with zero entries.
# The real file stays in the skill directory and is never published.
LEARN_TPL="$DEST/templates/learnings.md"
if [ -f "$LEARN_TPL" ]; then
  skill_name="$(basename "$SKILL_DIR")"
  sed "s/<skill-name>/${skill_name}/g" "$LEARN_TPL" > "$DEST/learnings.md"
fi
if grep -qE '^## [0-9]{4}-' "$DEST/learnings.md" 2>/dev/null; then
  die "learnings.md carries session entries — mark the skill so only the header is exported"
fi
if [ "$(wc -c < "$DEST/learnings.md")" -gt 2000 ]; then
  die "learnings.md is larger than the canonical header — session knowledge must stay local"
fi

echo "export-clean: $applied redaction rule(s) applied in $DEST (learnings.md = header only)"

if ! bash "$SCAN" "$DEST" --tree-only; then
  die "the export still contains forbidden terms — it is NOT publishable (see detail above)"
fi

echo "export-clean: tree is clean. History/owner still need verification before publishing:"
echo "  git -C <repo> log --all -p | grep -i <term>   ·   git remote -v"
