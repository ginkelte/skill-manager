# skill-manager

A **harness-agnostic** skill that governs how skills are written: structure, validation, wrappers
and — the core of it — a **self-learning** channel per skill.

It assumes nothing about the product: any agent harness that loads skills from a directory can use
it. Paths below use `$SKILLS_ROOT`, the directory your harness loads skills from. The scripts derive
it from their own location, so a clone works wherever you drop it.

> The rule it installs: **every skill has a `learnings.md`**. That is where the agent records what
> did not go smoothly: what it had to research, the error it had to debug, the restriction nobody
> had documented. It reads that file before improvising on a failure, and writes to it after
> solving one.

## Why it exists

A skill is procedural memory: it loads into every future session and changes how the agent works.
But a skill written once ages badly — the agent hits the same error, solves it, and the next
session hits it again because nothing was recorded. `learnings.md` is that record, and
`skill-manager` is the standard that makes it mandatory and searchable.

## Anatomy

```
skill-manager/
├── SKILL.md                          # the standard: create, edit, wrap, audit
├── references/
│   ├── learnings-standard.md         # full spec of the learnings standard
│   └── publication-export.md         # export + redaction + parity procedure
├── templates/
│   ├── learnings-clause.md           # ## Learnings block to paste into any skill
│   └── learnings.md                  # starter header for the learnings file
├── scripts/
│   ├── append-learning.sh            # atomic append with formatting
│   ├── audit-skills.py               # gap audit by origin (local/bundled/hub/archived)
│   ├── export-clean.sh               # copy to an export dir applying the redaction map
│   └── pii-scan.sh                   # publication gate: tree, history, authors, owner, PR refs
└── learnings.md                      # what this skill itself learned (dogfooding)
```

`learnings.md` ships here as **header only**: the append-only rules, the promotion rule and the
recording command, with zero entries. Session learnings are local knowledge — they stay in the skill
directory and are never published.

## Install

```bash
git clone <url-of-this-repo>.git
export SKILLS_ROOT="$HOME/skills"              # wherever your harness loads skills from
cp -r skill-manager "$SKILLS_ROOT/utilities/skill-manager"
chmod +x "$SKILLS_ROOT/utilities/skill-manager/scripts/"*
```

Most harnesses cache the skill loader per session: the skill shows up in the **next** session.
Quick check from a fresh process, using whatever list command your harness exposes:

```bash
skills list | grep skill-manager                # whatever your harness calls it
```

## Usage

**Create a skill** → follow `SKILL.md` § Workflows A: structure + `learnings.md` + the clause.

**Wrap an existing skill** → § Wrapper: three patterns (reference, extension, guard) and the hard
rule: *reference, do not copy*.

**Audit the standard** →

```bash
SM="$SKILLS_ROOT/utilities/skill-manager"
python3 "$SM/scripts/audit-skills.py" --summary
python3 "$SM/scripts/audit-skills.py" --root "$SKILLS_ROOT/workflow"    # a subtree
python3 "$SM/scripts/audit-skills.py" --fail-on-gaps                    # exit 1 on live gaps
```

**Record a finding** →

```bash
bash "$SKILLS_ROOT/utilities/skill-manager/scripts/append-learning.sh" "$SKILLS_ROOT/<category>/<skill>" \
  --title "403 reading cookies over CDP" \
  --symptom "CDP error 403 on Network.getAllCookies" \
  --cause  "Chrome started with --remote-debugging-pipe, no TCP port" \
  --fix    "relaunch with --remote-debugging-port=9222 and wait for /json/version" \
  --rule   "check /json/version before any CDP call"
```

Typical audit output:

```
origin    fml  lrn  clause    chars  skill
local     ok   ok   ok        19827  skill-manager
```

## The learnings loop

```
failure / blocker
   ├─ is it in learnings.md?  → grep → apply the recorded fix → done
   └─ no → solve it → append → does it apply to every future run? → promote to ## Common Pitfalls
```

Full detail (fields, taxonomy, size caps, promotion, good and bad examples):
[`references/learnings-standard.md`](references/learnings-standard.md).

## Publishing

Before publishing any artifact, two scripts must pass: `export-clean.sh` (copy + redaction) and
`pii-scan.sh` (gate over tree, history, authors, remote owner and PR refs). The procedure, including
why redacting the tree is not enough, is in
[`references/publication-export.md`](references/publication-export.md).

## Language

Every skill is written in **English**: `SKILL.md`, `references/`, `templates/`, `learnings.md`,
comments and script messages. Only content that must be in another language by nature (an email
template, the literal name of a local form) appears quoted as an example.

## Portability notes

`SKILL.md` was written against a real installation and then generalized, so a few things are worth
knowing before you rely on it:

- **Skills root**: everything is expressed as `$SKILLS_ROOT`; the scripts fall back to their own
  location. If your harness uses a different layout (flat instead of `<category>/<skill>/`), pass
  `--root` or set the variable.
- **Optional manifest**: `audit-skills.py` recognizes `.bundled_manifest` (`name:hash`) to classify
  skills that ship with the product. Without it, those skills simply read as `local`.
- **Frontmatter**: the standard keeps only universal fields and mentions harness-specific metadata
  as optional — add your own namespace if your loader reads one.
- **Publication gate**: the redaction map and the term list are plain text files you supply, outside
  the skill. The scripts ship no vocabulary of their own.

## License

MIT — see [LICENSE](LICENSE).
