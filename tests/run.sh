#!/usr/bin/env bash
# tests/run.sh — black-box test suite for skill-manager.
#
# Usage: bash tests/run.sh        (runs from any cwd; needs bash, python3, git)
#
# Prints "PASS <case>" / "FAIL <case> — <reason>" per case and a final
# "RESULT: N passed, M failed". Exit 0 only when every case passes.
#
# No network. The repository is only read: every fixture lives in a private
# mktemp(1) directory that the EXIT trap removes.
set -uo pipefail

cd "$(dirname "$0")/.." || { echo "tests: cannot cd to the repo root" >&2; exit 1; }
REPO="$(pwd)"
# $TMP lives one level down so that a wrong root derivation from
# $TMP/flat/scripts (scripts -> skill -> category) lands on $BASE, which holds
# only $TMP: it can never look like a skills root by accident.
BASE="$(mktemp -d "${TMPDIR:-/tmp}/skill-manager-tests.XXXXXX")"
TMP="$BASE/run"
mkdir -p "$TMP"
trap 'rm -rf "$BASE"' EXIT

PASSED=0
FAILED=0

ok()  { PASSED=$((PASSED + 1)); printf 'PASS %s\n' "$1"; }
bad() { FAILED=$((FAILED + 1)); printf 'FAIL %s — %s\n' "$1" "$2"; }

# Single-line snippet of a file (or command output) for FAIL evidence.
evidence() {
  if [ -f "${1:-}" ]; then
    head -c 400 "$1" 2>/dev/null | tr '\n' '|' | cut -c1-400
  else
    printf '<missing %s>' "${1:-}"
  fi
}

# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------
TERMS="$TMP/terms.txt"
printf 'zzqone\nzzqtwo\n' > "$TERMS"          # 2 lines, no comments
: > "$TMP/empty.map"                          # redaction map with 0 rules

# ---------------------------------------------------------------------------
# 1. syntax — bash -n on every .sh, py_compile on the .py
# ---------------------------------------------------------------------------
reason=""
for f in scripts/append-learning.sh scripts/export-clean.sh scripts/pii-scan.sh scripts/audit-skills.py; do
  [ -f "$f" ] || { reason="expected $f to exist"; break; }
done
if [ -z "$reason" ]; then
  for f in scripts/*.sh; do
    if ! err="$(bash -n "$f" 2>&1)"; then
      reason="bash -n $f failed: $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-300)"
      break
    fi
  done
fi
if [ -z "$reason" ]; then
  # PYTHONPYCACHEPREFIX keeps __pycache__ out of the repository.
  if ! err="$(PYTHONPYCACHEPREFIX="$TMP/pycache" python3 -m py_compile scripts/audit-skills.py 2>&1)"; then
    reason="py_compile scripts/audit-skills.py failed: $(printf '%s' "$err" | tr '\n' ' ' | cut -c1-300)"
  fi
fi
if [ -z "$reason" ]; then ok syntax; else bad syntax "$reason"; fi

# ---------------------------------------------------------------------------
# 2. clause parity — the `## Learnings` block must equal templates/learnings-clause.md
# ---------------------------------------------------------------------------
par_out="$(python3 - <<'PY'
import sys
from pathlib import Path

skill_lines = Path("SKILL.md").read_text(encoding="utf-8").splitlines()
template = Path("templates/learnings-clause.md").read_text(encoding="utf-8")

try:
    start = next(i for i, l in enumerate(skill_lines) if l.strip() == "## Learnings")
    end = next(i for i, l in enumerate(skill_lines) if i > start and l.strip() == "## Common Pitfalls")
except StopIteration:
    print("could not find both '## Learnings' and '## Common Pitfalls' in SKILL.md")
    sys.exit(1)

block = [
    l for l in skill_lines[start:end]
    if not l.lstrip().startswith("> Literal copy of")
]
got = "\n".join(block).rstrip() + "\n"
want = template.rstrip() + "\n"

if got == want:
    print("equal")
    sys.exit(0)

gl, wl = got.splitlines(), want.splitlines()
for i in range(max(len(gl), len(wl))):
    a = gl[i] if i < len(gl) else "<no line>"
    b = wl[i] if i < len(wl) else "<no line>"
    if a != b:
        print(f"first difference at line {i + 1}: SKILL.md={a[:160]!r} template={b[:160]!r}")
        break
sys.exit(1)
PY
)"
par_rc=$?
if [ "$par_rc" -eq 0 ]; then
  ok clause-parity
else
  bad clause-parity "expected the '## Learnings' block to be byte-identical to templates/learnings-clause.md; got $(printf '%s' "$par_out" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 3. size — SKILL.md must stay under the loader cap
# ---------------------------------------------------------------------------
skill_chars="$(wc -c < SKILL.md)"
if [ "$skill_chars" -le 20000 ]; then
  ok size
else
  bad size "expected SKILL.md <= 20000 chars, got $skill_chars"
fi

# ---------------------------------------------------------------------------
# 4. learnings publishable — no dated entries, under 2000 bytes
# ---------------------------------------------------------------------------
lrn_entries="$(grep -cE '^## [0-9]{4}-' learnings.md 2>/dev/null || true)"
lrn_entries="${lrn_entries:-0}"
lrn_bytes="$(wc -c < learnings.md)"
if [ "$lrn_entries" -eq 0 ] && [ "$lrn_bytes" -le 2000 ]; then
  ok learnings-publishable
else
  bad learnings-publishable "expected 0 '^## YYYY-' entries and <= 2000 bytes; got $lrn_entries entries, $lrn_bytes bytes"
fi

# ---------------------------------------------------------------------------
# 5. frontmatter — opening fence, non-empty name/description, real YAML,
#    and name == directory name in the canonical layout.
# ---------------------------------------------------------------------------
fm_out="$(python3 - "$REPO/SKILL.md" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
fence = text.startswith("---")
block = ""
if fence:
    end = text.find("\n---", 3)
    block = text[3:end] if end != -1 else ""
else:
    block = text

name = desc = ""
yaml_ok = "no"
yaml_err = ""
try:
    import yaml
except ImportError:
    yaml = None

if block:
    if yaml is not None:
        try:
            data = yaml.safe_load(block)
        except Exception as exc:  # unclosed quote, bad indentation, ...
            data = None
            yaml_err = str(exc).replace("\n", " ")
        if isinstance(data, dict):
            yaml_ok = "yes"
            name = data.get("name") if isinstance(data.get("name"), str) else ""
            desc = data.get("description") if isinstance(data.get("description"), str) else ""
    else:
        m = re.search(r"^name\s*:\s*(.+)$", block, re.MULTILINE)
        if m:
            name = m.group(1).strip().strip('"').strip("'")
        m = re.search(r"^description\s*:\s*(.+)$", block, re.MULTILINE)
        if m:
            desc = m.group(1).strip().strip('"').strip("'")

print("FENCE=" + ("yes" if fence else "no"))
print("YAML_AVAILABLE=" + ("yes" if yaml is not None else "no"))
print("YAML_OK=" + yaml_ok)
print("NAME=" + name.strip().replace("\n", " "))
print("DESC_LEN=" + str(len(desc.strip())))
if yaml_err:
    print("YAML_ERROR=" + yaml_err[:200])
PY
)"
fm_rc=$?
fm_fence="$(printf '%s\n' "$fm_out" | sed -n 's/^FENCE=//p')"
fm_yaml="$(printf '%s\n' "$fm_out" | sed -n 's/^YAML_OK=//p')"
fm_yaml_avail="$(printf '%s\n' "$fm_out" | sed -n 's/^YAML_AVAILABLE=//p')"
fm_name="$(printf '%s\n' "$fm_out" | sed -n 's/^NAME=//p')"
fm_desc_len="$(printf '%s\n' "$fm_out" | sed -n 's/^DESC_LEN=//p')"
fm_err="$(printf '%s\n' "$fm_out" | sed -n 's/^YAML_ERROR=//p')"

reason=""
if [ "$fm_rc" -ne 0 ]; then
  reason="frontmatter probe failed: $(printf '%s' "$fm_out" | tr '\n' ' ')"
elif [ "$fm_fence" != "yes" ]; then
  reason="expected SKILL.md to start with '---'; got '$(head -c 40 SKILL.md)'"
elif [ -z "$fm_name" ]; then
  reason="expected a non-empty 'name:'; got none"
elif [ "${fm_desc_len:-0}" -eq 0 ]; then
  reason="expected a non-empty 'description:'; got len=0"
elif [ "$fm_yaml_avail" = "yes" ] && [ "$fm_yaml" != "yes" ]; then
  reason="expected PyYAML to parse the frontmatter; got YAML_OK=no $fm_err"
elif [ "$fm_yaml" = "yes" ]; then
  dir_name="$(basename "$REPO")"
  matches=0
  [ "$fm_name" = "$dir_name" ] && matches=1
  if [ "$matches" -eq 0 ]; then
    # This worktree may be named after the branch (<name>-ci). The published
    # checkout is named after the repository, so accept only that exact case.
    remote_name="$(git -C "$REPO" remote get-url origin 2>/dev/null \
      | sed -e 's#/$##' -e 's#\.git$##' -e 's#.*/##')"
    case "$dir_name" in
      "$fm_name"-*) [ "$remote_name" = "$fm_name" ] && matches=1 ;;
    esac
  fi
  if [ "$matches" -eq 0 ]; then
    reason="expected name '$fm_name' to equal the skill directory name; got directory '$(basename "$REPO")'"
  fi
else
  reason="expected PyYAML to parse the frontmatter; got YAML_OK=no $fm_err"
fi
if [ -z "$reason" ]; then ok frontmatter; else bad frontmatter "$reason"; fi

# ---------------------------------------------------------------------------
# 6. audit in an installed layout — scripts derive <root>/<category>/<skill>
# ---------------------------------------------------------------------------
SB="$TMP/root/workflow/skill-manager"
mkdir -p "$SB"
cp -a SKILL.md learnings.md references templates scripts "$SB"/

aud_out="$(python3 "$SB/scripts/audit-skills.py" --root "$TMP/root" --show skill-manager 2>&1)"
aud_rc=$?
reason=""
if [ "$aud_rc" -ne 0 ]; then
  reason="expected exit 0; got exit $aud_rc: $(printf '%s' "$aud_out" | tr '\n' '|' | cut -c1-300)"
else
  aud_row="$(printf '%s\n' "$aud_out" | awk '/^[a-z]+ +[^ ]+/ && /  skill-manager$/ { print; exit }')"
  if [ -z "$aud_row" ]; then
    reason="expected a result row for skill-manager; got: $(printf '%s' "$aud_out" | tr '\n' '|' | cut -c1-300)"
  else
    # shellcheck disable=SC2086
    set -- $aud_row
    if [ "${2:-}" != "ok" ] || [ "${3:-}" != "ok" ] || [ "${4:-}" != "ok" ]; then
      reason="expected fml ok, lrn ok, clause ok; got row '$aud_row'"
    fi
  fi
fi

if [ -z "$reason" ]; then
  sum_out="$(python3 "$SB/scripts/audit-skills.py" --root "$TMP/root" --summary 2>&1)"
  sum_n="$(printf '%s\n' "$sum_out" | sed -n 's/^skills: \([0-9][0-9]*\).*/\1/p')"
  if [ -z "$sum_n" ] || [ "$sum_n" -lt 1 ]; then
    reason="expected --summary to report >= 1 skill; got: $(printf '%s' "$sum_out" | tr '\n' '|' | cut -c1-300)"
  fi
fi
if [ -z "$reason" ]; then ok audit-installed; else bad audit-installed "$reason"; fi

# ---------------------------------------------------------------------------
# 7. audit in a flat clone — must fail fast with guidance, never crawl /
# ---------------------------------------------------------------------------
mkdir -p "$TMP/flat/scripts"
cp scripts/audit-skills.py "$TMP/flat/scripts/"
flat_err="$TMP/flat.err"
# HOME is pinned to an empty directory so ~/skills cannot exist: the point of
# the case is the script's own derivation, not the developer's home layout.
mkdir -p "$TMP/emptyhome"
env -u SKILLS_ROOT HOME="$TMP/emptyhome" timeout 20 \
  python3 "$TMP/flat/scripts/audit-skills.py" >"$TMP/flat.out" 2>"$flat_err"
flat_rc=$?
reason=""
if [ "$flat_rc" -eq 124 ]; then
  reason="expected exit 2, got 124: the script walked the filesystem for 20s instead of failing fast"
elif [ "$flat_rc" -ne 2 ]; then
  reason="expected exit 2; got exit $flat_rc (stdout='$(evidence "$TMP/flat.out")' stderr='$(evidence "$flat_err")')"
elif ! grep -qE -- '--root|SKILLS_ROOT' "$flat_err"; then
  reason="expected stderr to mention --root or SKILLS_ROOT; got '$(evidence "$flat_err")'"
fi
if [ -z "$reason" ]; then ok audit-flat-clone; else bad audit-flat-clone "$reason"; fi

# ---------------------------------------------------------------------------
# 8. pii-scan.sh --show-terms must print the list once and exit 0 (the bug
#    printed the list and fell back into the argument loop: infinite output)
# ---------------------------------------------------------------------------
# head -c caps the output so a regression cannot fill the disk; PIPESTATUS[0]
# keeps timeout's own exit code.
PII_BLOCKLIST="$TERMS" timeout 10 bash scripts/pii-scan.sh --show-terms 2>"$TMP/st.err" \
  | head -c 65536 > "$TMP/st.out"
st_rc=${PIPESTATUS[0]}
st_lines=$(grep -c '' "$TMP/st.out" 2>/dev/null || true)
st_lines="${st_lines:-0}"
want_terms=$(grep -c '' "$TERMS")
reason=""
if [ "$st_rc" -eq 124 ]; then
  reason="expected exit 0, got 124: --show-terms never terminated (the print-then-loop bug)"
elif [ "$st_rc" -ne 0 ]; then
  reason="expected exit 0; got exit $st_rc (stdout='$(evidence "$TMP/st.out")' stderr='$(evidence "$TMP/st.err")')"
elif [ "$st_lines" -ne "$want_terms" ]; then
  reason="expected exactly $want_terms printed term(s); got $st_lines line(s): '$(evidence "$TMP/st.out")'"
elif [ "$st_lines" -gt 5 ]; then
  reason="expected <= 5 lines (no repetition); got $st_lines"
elif ! cmp -s "$TMP/st.out" "$TERMS"; then
  reason="expected the printed terms to match the list; got '$(evidence "$TMP/st.out")'"
fi
if [ -z "$reason" ]; then ok pii-show-terms; else bad pii-show-terms "$reason"; fi

# ---------------------------------------------------------------------------
# 9. placeholder author gate — 'maintainers' style identities must fail
# ---------------------------------------------------------------------------
PFX="$TMP/pii-fixture"
mkdir -p "$PFX"
printf 'fixture\n' > "$PFX/readme.txt"
git -C "$PFX" -c init.defaultBranch=main init -q
git -C "$PFX" -c user.name='acme maintainers' \
                -c user.email='maintainers@users.noreply.github.com' \
                -c commit.gpgsign=false add -A
git -C "$PFX" -c user.name='acme maintainers' \
                -c user.email='maintainers@users.noreply.github.com' \
                -c commit.gpgsign=false commit -qm "init"
reason=""
if ! git -C "$PFX" rev-parse --verify -q HEAD >/dev/null 2>&1; then
  reason="fixture setup failed: no commit in $PFX"
fi
PII_BLOCKLIST="$TERMS" bash scripts/pii-scan.sh "$PFX" >"$TMP/pii.out" 2>&1
pii_rc=$?
if [ -z "$reason" ]; then
  if [ "$pii_rc" -ne 1 ]; then
    reason="expected exit 1 (placeholder author); got exit $pii_rc: '$(evidence "$TMP/pii.out")'"
  elif ! grep -qi 'placeholder' "$TMP/pii.out"; then
    reason="expected output to mention 'placeholder'; got '$(evidence "$TMP/pii.out")'"
  fi
fi
if [ -z "$reason" ]; then ok pii-placeholder-author; else bad pii-placeholder-author "$reason"; fi

# ---------------------------------------------------------------------------
# 10. learnings gate — an export whose template carries entries must abort
# ---------------------------------------------------------------------------
EFX="$TMP/export-fixture"
mkdir -p "$EFX"
cp -a SKILL.md learnings.md references templates scripts "$EFX"/
printf '\n## 2026-01-01 — x\n\n- **Fix:** y\n' >> "$EFX/templates/learnings.md"
PII_EXPORT_MAP="$TMP/empty.map" PII_BLOCKLIST="$TERMS" \
  bash "$EFX/scripts/export-clean.sh" "$EFX" "$TMP/export-gate-dest" >"$TMP/gate.out" 2>&1
gate_rc=$?
reason=""
if [ "$gate_rc" -ne 1 ]; then
  reason="expected exit 1 (learnings with entries); got exit $gate_rc: '$(evidence "$TMP/gate.out")'"
elif ! grep -qi 'learnings' "$TMP/gate.out"; then
  reason="expected the message to mention learnings; got '$(evidence "$TMP/gate.out")'"
fi
if [ -z "$reason" ]; then ok export-learnings-gate; else bad export-learnings-gate "$reason"; fi

# ---------------------------------------------------------------------------
# 11. append-learning.sh — creates the canonical header and appends the entry
# ---------------------------------------------------------------------------
MINI="$TMP/mini-skill"
mkdir -p "$MINI"
printf -- '---\nname: mini\ndescription: "fixture skill for append-learning"\n---\n\n# Mini\n' > "$MINI/SKILL.md"
bash scripts/append-learning.sh "$MINI" --title t --symptom s --fix f >"$TMP/app.out" 2>&1
app_rc=$?
reason=""
if [ "$app_rc" -ne 0 ]; then
  reason="expected exit 0; got exit $app_rc: '$(evidence "$TMP/app.out")'"
elif [ ! -f "$MINI/learnings.md" ]; then
  reason="expected $MINI/learnings.md to exist; it does not"
else
  hdr_lines="$(grep -c '' templates/learnings.md)"
  sed "s/<skill-name>/$(basename "$MINI")/g" templates/learnings.md > "$TMP/mini-want"
  head -n "$hdr_lines" "$MINI/learnings.md" > "$TMP/mini-got"
  if ! cmp -s "$TMP/mini-want" "$TMP/mini-got"; then
    reason="expected the file to start with the canonical header; got '$(evidence "$TMP/mini-got")'"
  elif ! grep -qE '^## [0-9]{4}-[0-9]{2}-[0-9]{2} — t$' "$MINI/learnings.md"; then
    reason="expected an entry heading '## YYYY-MM-DD — t'; got '$(tail -n 6 "$MINI/learnings.md" | tr '\n' '|')'"
  elif ! grep -qF -- '- **Symptom:** s' "$MINI/learnings.md" || ! grep -qF -- '- **Fix:** f' "$MINI/learnings.md"; then
    reason="expected the entry to carry 'Symptom: s' and 'Fix: f'; got '$(tail -n 6 "$MINI/learnings.md" | tr '\n' '|')'"
  fi
fi
if [ -z "$reason" ]; then ok append-learning; else bad append-learning "$reason"; fi

# ---------------------------------------------------------------------------
# 12. clean export — header-only learnings.md, no compiled caches
# ---------------------------------------------------------------------------
DEST="$TMP/export-clean-dest"
PII_EXPORT_MAP="$TMP/empty.map" PII_BLOCKLIST="$TERMS" \
  bash scripts/export-clean.sh "$REPO" "$DEST" >"$TMP/clean.out" 2>&1
clean_rc=$?
reason=""
if [ "$clean_rc" -ne 0 ]; then
  reason="expected exit 0; got exit $clean_rc: '$(evidence "$TMP/clean.out")'"
elif [ ! -f "$DEST/learnings.md" ]; then
  reason="expected $DEST/learnings.md to exist; it does not"
else
  dest_bytes="$(wc -c < "$DEST/learnings.md")"
  dest_entries="$(grep -cE '^## [0-9]{4}-' "$DEST/learnings.md" 2>/dev/null || true)"
  dest_entries="${dest_entries:-0}"
  pycache="$(find "$DEST" -name '__pycache__' -type d 2>/dev/null | head -n 3 | tr '\n' ' ')"
  if [ "$dest_bytes" -gt 2000 ]; then
    reason="expected exported learnings.md <= 2000 bytes; got $dest_bytes"
  elif [ "$dest_entries" -ne 0 ]; then
    reason="expected 0 session entries in the export; got $dest_entries"
  elif [ -n "$pycache" ]; then
    reason="expected no __pycache__ in the export; got '$pycache'"
  fi
fi
if [ -z "$reason" ]; then ok export-clean; else bad export-clean "$reason"; fi

# ---------------------------------------------------------------------------
printf '\nRESULT: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
