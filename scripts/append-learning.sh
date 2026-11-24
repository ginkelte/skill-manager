#!/usr/bin/env bash
# append-learning.sh — atomic append of an entry to <skill>/learnings.md
#
# Usage:
#   append-learning.sh <skill-dir> --title "..." [--context "..." ] [--symptom "..." ]
#                                  [--cause "..." ] [--fix "..." ] [--rule "..." ]
#
# - Creates learnings.md with the standard header if it does not exist.
# - Never edits or deletes previous entries (append-only).
# - Fails if --title is missing or if the directory has no SKILL.md.
set -euo pipefail

die() { printf 'append-learning: %s\n' "$1" >&2; exit 1; }

case "${1:-}" in
  -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
esac

[ $# -ge 1 ] || die "usage: append-learning.sh <skill-dir> --title \"...\" [--symptom ... --cause ... --fix ... --rule ... --context ...]"
SKILL_DIR="${1%/}"; shift

[ -d "$SKILL_DIR" ] || die "directory does not exist: $SKILL_DIR"
[ -f "$SKILL_DIR/SKILL.md" ] || die "$SKILL_DIR does not look like a skill (missing SKILL.md)"

# Untouchable paths: the curator archives, the hub updates itself and the snapshot is a mirror.
case "$SKILL_DIR" in
  */.archive/*|*/.hub/*|*/.curator_backups/*|*/snapshots/skills/*)
    die "unwritable path: $SKILL_DIR (archive/hub/curator/snapshot) — the source of truth is <skills-root>/<category>/<skill>" ;;
esac

TITLE=""; CTX=""; SYM=""; CAUSE=""; FIX=""; RULE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --title)   [ $# -ge 2 ] || die "--title requires a value";   TITLE="$2"; shift 2 ;;
    --context) [ $# -ge 2 ] || die "--context requires a value"; CTX="$2";   shift 2 ;;
    --symptom) [ $# -ge 2 ] || die "--symptom requires a value"; SYM="$2";   shift 2 ;;
    --cause)   [ $# -ge 2 ] || die "--cause requires a value";   CAUSE="$2"; shift 2 ;;
    --fix)     [ $# -ge 2 ] || die "--fix requires a value";     FIX="$2";   shift 2 ;;
    --rule)    [ $# -ge 2 ] || die "--rule requires a value";    RULE="$2";  shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "unknown flag: $1" ;;
  esac
done

[ -n "$TITLE" ] || die "missing --title (required: it is what makes the entry searchable)"
[ -n "$FIX$SYM$RULE" ] || die "an entry with no --symptom, --fix or --rule is useless: add at least one"

# A newline inside a field would break the format (fake heading / split bullet).
TITLE="$(printf '%s' "$TITLE" | tr '\n\r' '  ')"
CTX="$(printf '%s' "$CTX" | tr '\n\r' '  ')"
SYM="$(printf '%s' "$SYM" | tr '\n\r' '  ')"
CAUSE="$(printf '%s' "$CAUSE" | tr '\n\r' '  ')"
FIX="$(printf '%s' "$FIX" | tr '\n\r' '  ')"
RULE="$(printf '%s' "$RULE" | tr '\n\r' '  ')"

FILE="$SKILL_DIR/learnings.md"
if [ ! -f "$FILE" ]; then
  skill_name="$(basename "$SKILL_DIR")"
  tpl="$(dirname "$0")/../templates/learnings.md"
  if [ -f "$tpl" ]; then
    # Single source: the header comes from the template, not from a parallel heredoc.
    sed "s/<skill-name>/$skill_name/g" "$tpl" > "$FILE"
  else
    {
      printf '# Learnings — %s\n\n' "$skill_name"
      printf '> Append-only in the body. One entry per non-obvious finding.\n'
      printf '> The only allowed mutation is adding a marker line\n'
      printf '> (`⚠️ superseded` / `→ promoted`) at the end of an existing entry.\n'
      printf '> Format: `skill_view('"'"'skill-manager'"'"', file_path='"'"'references/learnings-standard.md'"'"')`.\n'
    } > "$FILE"
  fi
fi

# Normalize the body: internal newlines are preserved, the block stays indented.
block="$(
  printf '\n## %s — %s\n\n' "$(date +%Y-%m-%d)" "$TITLE"
  [ -n "$CTX" ]   && printf -- '- **Context:** %s\n' "$CTX"
  [ -n "$SYM" ]   && printf -- '- **Symptom:** %s\n' "$SYM"
  [ -n "$CAUSE" ] && printf -- '- **Cause:** %s\n' "$CAUSE"
  [ -n "$FIX" ]   && printf -- '- **Fix:** %s\n' "$FIX"
  [ -n "$RULE" ]  && printf -- '- **Rule:** %s\n' "$RULE"
  true
)"

printf '%s\n' "$block" >> "$FILE"
printf 'ok: entry appended to %s\n' "$FILE"
