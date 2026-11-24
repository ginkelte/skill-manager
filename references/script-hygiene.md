# Script hygiene for the scripts a skill ships

The scripts are the part of a skill that runs unattended: from cron, from an export, on someone
else's layout. A wrong exit code or a swallowed `stderr` does not degrade the skill — it publishes
the wrong thing or hangs a job nobody is watching.

## Argument parsing: every terminal branch ends the loop

```bash
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)    sed -n '2,12p' "$0"; exit 0 ;;
    --show-terms) print_list; exit 0 ;;
    --terms)      [ $# -ge 2 ] || die "--terms requires a file"; LIST="$2"; shift 2 ;;
    -*)           die "unknown flag: $1" ;;
    *)            DIR="${1%/}"; shift ;;
  esac
done
```

- **An arm that prints but neither `shift`s nor `exit`s loops forever.** The loop re-reads the same
  `$1`, so the symptom is *output repeating*, not an error message — easy to miss in a pipe and easy
  to blame on the terminal. `--help` and `--show-terms` are the classic victims: they look terminal,
  and rewriting them as a `case` arm is where the `exit 0` gets dropped.
- Every arm either consumes the argument or terminates. Nothing else is allowed.
- With `set -u`, read the raw positional as `${1:-}`: a no-argument call must print usage, not die
  with `line N: 1: unbound variable`.
- `-h|--help` is checked **before** the argument parser, otherwise `--help` is treated as a path.

## Exit codes mean the same thing in every script

`0` success · `1` the gate failed (the answer is "not clean") · `2` usage or input error (the
caller's mistake). Document them in the header block; a caller that cannot distinguish 1 from 2
cannot decide whether to fix the artifact or the invocation.

Order of checks: validate arguments → validate that inputs exist → do the work → verify → report.

- **Fail with the fix, not with a diagnosis:** `echo "…: missing term list — set $VAR or create
  <root>/../references/<file>" >&2; exit 2` costs one line and saves the next agent the
  investigation. A traceback is not a message.
- A rejected input deserves the same treatment: `error: <dir> is not a skills root — pass --root
  <dir> or set $SKILLS_ROOT`.

## Never silence the step whose success you report

`sed -i … 2>/dev/null`, `grep … 2>/dev/null || true`, `cmd 2>/dev/null` — each turns a failed
operation into a silent success, and the next line of the script then *certifies* it.

- A gate that cannot fail is decoration: if the verification step swallows its own errors, the
  "clean" it prints means nothing.
- Escape data that goes into `sed` (`sed 's/[][\/$*.^|]/\\&/g'`) instead of hiding the error the
  bad expression raises.

## Gates regenerate; they do not truncate

When an exported file must carry no data, rebuild it from its template (placeholder filled with the
real name) and abort if a record survived. `: > file` produces a 0-byte artifact that teaches the
reader nothing and erases the evidence that a contract used to live there.

```bash
sed "s/<skill-name>/${skill_name}/g" "$DEST/templates/learnings.md" > "$DEST/learnings.md"
grep -qE '^## [0-9]{4}-' "$DEST/learnings.md" && die "records leaked into the export"
[ "$(wc -c < "$DEST/learnings.md")" -le 2000 ] || die "larger than the canonical header"
```

## Search order for files outside the skill

Explicit variable → the path derived from the root → the script's own relative path; first one that
**exists** wins, and when none does, name the path to create. Never a single hard-coded absolute path:
it is wrong on every machine except the one that wrote it.

## Test matrix before shipping a change

1. **`bash -n` / `python3 -m py_compile`** after every edit, before anything else.
2. **Every flag**, with and without its required input, and one unknown flag (expect exit 2).
3. **The same script from two layouts**: the installed tree (root derives correctly) and a flat copy
   (a clone, where it must fail fast with the instruction instead of scanning the filesystem).
4. **A fixture that hits and one that does not**, for anything that gates — the second proves the
   first is not hard-wired.
5. **Read the exit code** (`; echo $?`), never the last line of output.

## Do not ship build junk

Compiled caches (`__pycache__/`, `*.pyc`) appear the moment you run `py_compile` on a shipped script.
Drop them in the export step — `find "$DEST" -name __pycache__ -type d -prune -exec rm -rf {} +` — and
ignore them in `.gitignore`; do not rely on remembering to delete them by hand.
