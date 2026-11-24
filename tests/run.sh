#!/usr/bin/env bash
# tests/run.sh — black-box test suite for skill-manager.
#
# Usage: bash tests/run.sh   (any cwd; needs bash, git, GNU timeout, python3 + PyYAML)
#
# Prints "PASS <case>" / "FAIL <case> — <reason>" per case and a final
# "RESULT: N passed, M failed". Exit 0 only when every case passes.
#
# No network. The repository is only read: every fixture lives in a private
# mktemp(1) directory that the EXIT trap removes.
set -uo pipefail

# Hard prerequisites: without them a case would blame the code under test for a
# broken toolchain. `timeout` is GNU coreutils; macOS ships it as `gtimeout`.
missing=""
for tool in bash git python3; do
  command -v "$tool" >/dev/null 2>&1 || missing="${missing:+$missing, }$tool"
done
if ! command -v timeout >/dev/null 2>&1; then
  echo "tests: missing prerequisite: timeout (on macOS install coreutils and use gtimeout)" >&2
  exit 2
fi
if [ -n "$missing" ]; then
  echo "tests: missing prerequisites: $missing" >&2
  exit 2
fi
python3 -c 'import yaml' 2>/dev/null || {
  echo "tests: missing prerequisite: PyYAML (python3 -m pip install pyyaml) — the frontmatter case cannot validate YAML without it" >&2
  exit 2
}

cd "$(dirname "$0")/.." || { echo "tests: cannot cd to the repo root" >&2; exit 1; }
REPO="$(pwd)"
# The flat-clone case gets its own sandbox ($BASE/flatbase): the shared $TMP
# accumulates fixtures with SKILL.md files (mini-skill, export-fixture) that make
# $BASE match `*/*/SKILL.md`, so a wrong root derivation could succeed by
# accident. $FLAT_BASE never holds a SKILL.md, so a wrong root cannot look like
# a skills root either.
BASE="$(mktemp -d "${TMPDIR:-/tmp}/skill-manager-tests.XXXXXX")"
TMP="$BASE/run"
mkdir -p "$TMP"
trap 'rm -rf "$BASE"' EXIT
# Snapshot before any case runs: the suite must not touch the repository, not
# even when the checkout already carries local edits (e.g. a modified script).
REPO_STATUS_BEFORE="$TMP/repo-status.before"
git -C "$REPO" status --porcelain > "$REPO_STATUS_BEFORE" 2>/dev/null || : > "$REPO_STATUS_BEFORE"

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

# Drop exactly one known annotation line. A prefix test (`> Literal copy of`)
# would let divergent prose hide under that prefix and pass parity.
ANNOTATION = (
    "> Literal copy of `templates/learnings-clause.md` — "
    "edit both together (the audit checks presence, not parity)."
)
block = [
    l for l in skill_lines[start:end]
    if l.strip() != ANNOTATION
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
# 3. size — SKILL.md must stay under the loader cap (characters, not bytes:
#    multi-byte UTF-8 makes wc -c overstate the length the loader sees)
# ---------------------------------------------------------------------------
skill_chars="$(python3 -c "print(len(open('SKILL.md', encoding='utf-8').read()))")"
if [ "$skill_chars" -le 20000 ]; then
  ok size
else
  bad size "expected SKILL.md <= 20000 characters, got $skill_chars"
fi

# ---------------------------------------------------------------------------
# 4. learnings publishable — no dated entries, under 2000 bytes
# ---------------------------------------------------------------------------
reason=""
if [ ! -f learnings.md ]; then
  reason="expected learnings.md at the repo root; it does not exist"
else
  lrn_entries="$(grep -cE '^## [0-9]{4}-' learnings.md)"
  lrn_bytes="$(wc -c < learnings.md)"
  if [ "$lrn_entries" -ne 0 ] || [ "$lrn_bytes" -gt 2000 ]; then
    reason="expected 0 '^## YYYY-' entries and <= 2000 bytes; got $lrn_entries entries, $lrn_bytes bytes"
  fi
fi
if [ -z "$reason" ]; then ok learnings-publishable; else bad learnings-publishable "$reason"; fi

# ---------------------------------------------------------------------------
# 5. frontmatter — opening fence, non-empty name/description, real YAML,
#    and name == the skill's repository name (directory only if no remote).
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
elif [ "$fm_yaml_avail" != "yes" ]; then
  reason="PyYAML is not importable by python3 — install it (python3 -m pip install pyyaml); the frontmatter cannot be validated"
elif [ "$fm_yaml" != "yes" ]; then
  reason="expected valid YAML frontmatter; got YAML_OK=no $fm_err"
else
  # `name` identifies the skill. A canonical checkout is named after it; a
  # worktree or a locally renamed clone is not, so fall back to the repository
  # name from the remote, and to the directory only when there is no remote.
  dir_name="$(basename "$REPO")"
  remote_name="$(git -C "$REPO" remote get-url origin 2>/dev/null \
    | sed -e 's#/$##' -e 's#\.git$##' -e 's#.*/##')"
  expected_name="${remote_name:-$dir_name}"
  if [ "$fm_name" != "$expected_name" ]; then
    reason="expected name '$fm_name' to equal the skill name '$expected_name'; got directory '$dir_name'"
  fi
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
FLAT_BASE="$BASE/flatbase"
mkdir -p "$FLAT_BASE/run/flat/scripts"
cp scripts/audit-skills.py "$FLAT_BASE/run/flat/scripts/"
flat_err="$FLAT_BASE/flat.err"
# HOME is pinned to an empty directory so ~/skills cannot exist: the point of
# the case is the script's own derivation, not the developer's home layout.
mkdir -p "$FLAT_BASE/emptyhome"
env -u SKILLS_ROOT HOME="$FLAT_BASE/emptyhome" timeout 20 \
  python3 "$FLAT_BASE/run/flat/scripts/audit-skills.py" >"$FLAT_BASE/flat.out" 2>"$flat_err"
flat_rc=$?
reason=""
if [ "$flat_rc" -eq 124 ]; then
  reason="expected exit 2, got 124: the script walked the filesystem for 20s instead of failing fast"
elif [ "$flat_rc" -ne 2 ]; then
  reason="expected exit 2; got exit $flat_rc (stdout='$(evidence "$FLAT_BASE/flat.out")' stderr='$(evidence "$flat_err")')"
elif ! grep -qE -- '--root|SKILLS_ROOT' "$flat_err"; then
  reason="expected stderr to mention --root or SKILLS_ROOT; got '$(evidence "$flat_err")'"
fi
if [ -z "$reason" ]; then ok audit-flat-clone; else bad audit-flat-clone "$reason"; fi

# ---------------------------------------------------------------------------
# 8. pii-scan.sh --show-terms must print the list once and exit 0 (the bug
#    printed the list and fell back into the argument loop: infinite output)
# ---------------------------------------------------------------------------
# The output is capped so a regression cannot fill the disk; PIPESTATUS[0]
# keeps timeout's own exit code. Diagnose by line count FIRST: when the loop
# re-enters, `head -c` closes the pipe, sed dies of SIGPIPE and the script's
# fallback reports exit 2 — not a 124 timeout, and not the missing-list error.
PII_BLOCKLIST="$TERMS" timeout 10 bash scripts/pii-scan.sh --show-terms 2>"$TMP/st.err" \
  | head -c 65536 > "$TMP/st.out"
st_rc=${PIPESTATUS[0]}
st_lines=$(grep -c '' "$TMP/st.out" 2>/dev/null || true)
st_lines="${st_lines:-0}"
want_terms=$(grep -c '' "$TERMS")
reason=""
if [ "$st_lines" -ne "$want_terms" ]; then
  reason="expected $want_terms lines, got $st_lines: --show-terms re-entered the argument loop (stderr='$(evidence "$TMP/st.err")')"
elif [ "$st_rc" -eq 124 ]; then
  reason="expected exit 0, got 124: --show-terms timed out"
elif [ "$st_rc" -ne 0 ]; then
  reason="expected exit 0; got exit $st_rc (stdout='$(evidence "$TMP/st.out")' stderr='$(evidence "$TMP/st.err")')"
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
mkdir -p "$TMP/export-pre"; printf 'keep\n' > "$TMP/export-pre/keepme.txt"
PII_EXPORT_MAP="$TMP/empty.map" PII_BLOCKLIST="$TERMS" \
  bash scripts/export-clean.sh . "$TMP/export-pre" --force >"$TMP/gate-pre.out" 2>&1
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
elif [ -e "$TMP/export-gate-dest" ]; then
  # A failed export must not leave anything behind: the destination did not exist
  # before this run, so export-clean.sh removes it.
  reason="expected the aborted export to leave no destination; got '$(ls -A "$TMP/export-gate-dest" 2>/dev/null | tr '\n' ' ')'"
elif [ ! -f "$TMP/export-pre/keepme.txt" ]; then
  reason="expected a pre-existing destination to survive the abort; keepme.txt is gone"
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
  pycache="$(find "$DEST" -name '__pycache__' -type d 2>/dev/null | head -n 3 | tr '\n' ' ')"
  # Byte-for-byte canonical header: a literal copy of the source learnings.md
  # with an extra short note would slip past a size/entry check.
  # export-clean substitutes the source directory's basename; this checkout may
  # be a worktree (`<repo>-ci`), so derive it instead of hardcoding the name.
  export_name="$(basename "$REPO")"
  if ! cmp -s "$DEST/learnings.md" <(sed "s/<skill-name>/${export_name}/g" templates/learnings.md); then
    reason="expected the exported learnings.md to be exactly the canonical header; got '$(evidence "$DEST/learnings.md")'"
  elif [ -n "$pycache" ]; then
    reason="expected no __pycache__ in the export; got '$pycache'"
  fi
fi
if [ -z "$reason" ]; then ok export-clean; else bad export-clean "$reason"; fi

# ---------------------------------------------------------------------------
# 13. pii-term-hit — a term with a regex metacharacter is escaped and matched,
#     and export-clean refuses a tree that carries it (positive PAT coverage).
# ---------------------------------------------------------------------------
HITFX="$TMP/pii-hit"
TERMS_HIT="$TMP/hit-terms.txt"
printf 'qz.a\n' > "$TERMS_HIT"                  # `.` is a regex metacharacter
mkdir -p "$HITFX/references"
cp SKILL.md learnings.md "$HITFX"/
cp -a templates references "$HITFX"/
printf 'leak: qz.a\n' > "$HITFX/references/leak.txt"

PII_BLOCKLIST="$TERMS_HIT" bash scripts/pii-scan.sh "$HITFX" --tree-only \
  >"$TMP/hit.out" 2>&1
hit_rc=$?
reason=""
if [ "$hit_rc" -ne 1 ]; then
  reason="expected exit 1 (literal hit); got exit $hit_rc: '$(evidence "$TMP/hit.out")'"
elif ! grep -qF 'qz.a' "$TMP/hit.out"; then
  reason="expected the report to show the hit 'qz.a'; got '$(evidence "$TMP/hit.out")'"
fi
if [ -z "$reason" ]; then
  PII_EXPORT_MAP="$TMP/empty.map" PII_BLOCKLIST="$TERMS_HIT" \
    bash scripts/export-clean.sh "$HITFX" "$TMP/pii-hit-dest" >"$TMP/hit-export.out" 2>&1
  hit_export_rc=$?
  if [ "$hit_export_rc" -eq 0 ]; then
    reason="expected export-clean to refuse a tree containing 'qz.a'; it exited 0"
  elif ! grep -qiE 'not publishable|forbidden' "$TMP/hit-export.out"; then
    reason="expected export-clean to explain the tree is not publishable; got '$(evidence "$TMP/hit-export.out")'"
  fi
fi
if [ -z "$reason" ]; then ok pii-term-hit; else bad pii-term-hit "$reason"; fi

# ---------------------------------------------------------------------------
# 14. pii-show-terms-no-list — --show-terms with a missing list must exit 2
#     with guidance (the branch where the print-then-loop bug used to live)
# ---------------------------------------------------------------------------
# Run an isolated copy: the script's own `<root>/../references` candidates must
# not pick up a real blocklist from wherever this checkout happens to live.
NT_SCAN="$TMP/no-terms/scripts/pii-scan.sh"
mkdir -p "$(dirname "$NT_SCAN")"
cp scripts/pii-scan.sh "$NT_SCAN"
PII_BLOCKLIST="$TMP/no-such-blocklist.txt" bash "$NT_SCAN" --show-terms \
  >"$TMP/noterms.out" 2>&1
nt_rc=$?
reason=""
if [ "$nt_rc" -ne 2 ]; then
  reason="expected exit 2 (missing term list); got exit $nt_rc: '$(evidence "$TMP/noterms.out")'"
elif ! grep -qiE 'PII_BLOCKLIST|create .*blocklist' "$TMP/noterms.out"; then
  reason="expected the message to mention PII_BLOCKLIST or creating the list; got '$(evidence "$TMP/noterms.out")'"
fi
if [ -z "$reason" ]; then ok pii-show-terms-no-list; else bad pii-show-terms-no-list "$reason"; fi

# ---------------------------------------------------------------------------
# 15. repo-intact — the suite only reads the repository; exporting it must not
#     leave a modified or untracked file behind (compared with the snapshot)
# ---------------------------------------------------------------------------
git -C "$REPO" status --porcelain > "$TMP/repo-status.after" 2>&1
reason=""
if ! cmp -s "$REPO_STATUS_BEFORE" "$TMP/repo-status.after"; then
  reason="the suite changed the repository; status now: '$(evidence "$TMP/repo-status.after")'"
fi
if [ -z "$reason" ]; then ok repo-intact; else bad repo-intact "$reason"; fi

# ---------------------------------------------------------------------------
printf '\nRESULT: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
