---
name: skill-manager
description: "Use when creating, editing, wrapping or auditing a skill."
version: 1.1.0
author: skill-manager maintainers
license: MIT
tags: [skills, harness, standard, learnings, authoring, wrapper]
# Add `metadata.<your-harness>` only if your harness reads its own namespace.
---

# Skill Manager

Single standard for **creating, editing, wrapping and auditing** skills in any agent harness that
loads skills from a directory: structure, validation and — above all — the **learnings clause**.

`$SKILLS_ROOT` is that directory (`$SKILLS_ROOT/<category>/<skill>/`). The scripts derive it from
their own location; examples assume it is exported.

## Overview

A skill is procedural memory: it loads into every future session and changes how work gets done.
That is why it is written differently from a document: a trigger in the `description`, an actionable
body, measured pitfalls, and a channel so the next agent does not repeat the same mistakes.

That channel is `learnings.md`, next to `SKILL.md`: append-only, one entry per finding that cost time —
the error debugged, the undocumented restriction, the 20-minute investigation. Before improvising on a failure, the agent **reads**
that file; after resolving, it **writes**. What becomes stable moves up to `## Common Pitfalls`.

## When to Use

Yes, whenever:

- You are going to **create** a skill (through your harness's tool/installer, or by hand).
- You are going to **edit** the `SKILL.md`, a `references/*.md`, a script or the frontmatter of any skill.
- You are asked for a **wrapper**: a skill that wraps, extends or composes another one.
- You are asked to **audit**, **retrofit**, **normalize** or "update the skills to the new standard".
- An existing skill failed you and you are about to improvise: look in its `learnings.md` first.

No, when:

- The question is **which** skills should exist, be pruned or published → the skill-curation skill of
  your installation, if you have one (not covered here).
- The question is how a skill travels to your installation's repo (snapshot, rsync, deploy) → the
  sync skill you use; this document assumes one exists and does not reimplement it.
- You are writing the `SKILL.md` of a skill that **ships with the harness package** → follow the
  harness's own authoring reference for package frontmatter rules. The learnings clause
  still applies here.

## 🚨 Regime: where a skill's truth lives

Verify it in any installation — the numbers change, the method does not:

| What | How to check it |
|---|---|
| Where the truth lives | `ls "$SKILLS_ROOT"` — plain local files; the root is usually **not** a git repo |
| How many skills exist and in what state | `audit-skills.py --summary` → total · live · archived |
| Which ones ship with the harness | `.bundled_manifest` in the root, if the harness keeps one |
| Are they published to a repo? | the scheduler's job config — look for a snapshot job |

Consequences that are not negotiable:

1. **Truth = local.** The file an agent edits is `$SKILLS_ROOT/<category>/<skill>/...`.
   The backup repo only receives a **copy** through the periodic snapshot (cron), which opens
   its own PR. **Never** edit the copy inside the backup repo's snapshot path: rsync deletes it.
2. **You edit locally, you do not open a PR by hand** for skills. The PR is opened by the snapshot job and
   the cron generates it. (If your installation also versions scripts, the truth may be the other way
   around: check your pipeline before editing a script by hand.)
3. **The loader is cached per session.** A skill created now will not load in this session, even if it
   is perfect on disk. Verify with the harness's skill list (a fresh process does see it) and
   leave the real load test for a fresh session.
4. **`.archive/`, `.hub/`, `.curator_backups/` are off-limits.** The curator archives by disuse;
   retrofitting an archived skill is wasted work.

## Mandatory standard (every new skill)

Minimum checklist. Anything that fails it is not declared "ready":

- [ ] **Valid frontmatter**: first byte `---`, closing `\n---\n`, `name` (≤64, lowercase-hyphen),
      `description` (≤1024; `skill_manage` requires **≤60** when creating).
- [ ] **`description` = trigger, not summary.** Format `Use when <class of trigger>.`. Without
      this the skill never loads, because only its description enters the system prompt.
- [ ] **Actionable body**: `## Overview` + `## When to Use` (with counter-triggers) +
      exact command/code sections + `## Common Pitfalls` + `## Verification Checklist`.
- [ ] **`learnings.md`** created from `templates/learnings.md`.
- [ ] **Learnings clause** pasted into the `SKILL.md` (exact text in
      `templates/learnings-clause.md`, do not rewrite it by hand).
- [ ] **Size**: target 8–14k chars; >20k → move detail to `references/<topic>.md`.
- [ ] **English only**: `SKILL.md`, `references/`, `templates/`, `learnings.md`, comments and
      script messages. Quotations in another language, marked as examples.
- [ ] Harness-specific frontmatter, **if yours reads one** (e.g. `metadata.<harness>.related_skills`).
- [ ] **If it is going to be public**: `pii-scan.sh` with 0 hits in the tree **and** history/owner, and
      the tree exported with `export-clean.sh` (not by hand). `learnings.md` goes out header-only.
- [ ] **Shareable**: no product path, CLI name or metadata namespace → `references/harness-agnostic.md`.
- [ ] **Attributable**: commit author = the publishing account (noreply), never a placeholder.
- [ ] **No secrets, no browser profiles, no DBs** inside the skill directory: the
      snapshot publishes whatever is there. `rsync` already excludes `chrome-*profile/`, but **not** `.db`
      or binaries, and the secret masker usually processes only UTF-8: look for
      `except UnicodeDecodeError` in your snapshot script to confirm it.

## Language: English only

Every skill is written in **English**, consistently: `SKILL.md`, `references/`, `templates/`,
`learnings.md`, frontmatter values, code comments and script messages. Chat stays in the user's
language; the artifact does not.

**Why:** a skill is loaded into prompts and may be shared, reviewed or published. A half-translated
artifact breaks greps, confuses reviewers and turns a general-purpose skill into a personal one.

**Marked exceptions:** content that must be in another language by nature — an email template for
Spanish speakers, the literal name of a local form. Quote it as an example; the rest stays English.

## The learnings clause (Principles 1 and 2)

Two pieces, always together:

**a) The file** `$SKILLS_ROOT/<category>/<skill>/learnings.md` — append-only **in the body**,
one entry per non-obvious finding. The **only** allowed mutation is appending a marker line
(`⚠️ superseded` / `→ promoted`) at the end of an existing entry: prior text is never rewritten nor
deleted.

**b) The clause in the `SKILL.md`** — a `## Learnings` block that (1) declares that the file
exists, (2) says **how to consult it** when there is an error or a block, (3) says **how to record** a
new finding, (4) says when to **promote** the lesson to `## Common Pitfalls`.

The text is copied from `templates/learnings-clause.md` (single source); the detail — fields,
taxonomy, caps, examples, retrofit matrix — lives in `references/learnings-standard.md`.

**The loop, in three lines:**

```bash
# 1. before improvising on a failure
grep -in -A8 'error\|failed\|blocked' "$SKILLS_ROOT/<category>/<skill>/learnings.md"
# 2. if found: apply the recorded fix
# 3. if it was not there: solve it and record it
"$SKILLS_ROOT/<category>/skill-manager/scripts/append-learning.sh" \
  "$SKILLS_ROOT/<category>/<skill>" --title "..." --symptom "..." --cause "..." --fix "..." --rule "..."
```

## Wrapper: how to wrap a skill

"Wrapper" = a new skill whose job is to orchestrate another one. Three forms, in order of
preference:

1. **Reference (composition)** — the wrapper does not copy the other flow: it invokes it.
   ```markdown
   ## Step 1 — Ingest
   Load `skill_view('<skill-base>')` and follow its ingest flow as is. Do not reimplement it:
   if they diverge, the base skill wins.
   ```
   If the harness reads a metadata block, declare `related_skills: [<skill-base>]` there.

2. **Extension (new mode)** — the wrapper adds a mode or phase the base does not have (e.g. "besides
   creating, retrofit in batch"). The base stays untouched; the wrapper explicitly declares which
   steps it replaces and which it inherits.

3. **Guard (pre/post condition)** — the wrapper does not produce the result: it verifies it. E.g. "before
   saying 'ready', run the validation checklist". Useful when the base skill already exists and you do
   not want to touch it.

Hard wrapper rules:

- **A single source of truth.** If the wrapper starts duplicating steps from the base, it breaks the
  first time the base changes. Reference, do not copy.
- **Declare precedence**: "if the base and this skill contradict each other, X wins". Without that, a
  future agent invents the tie-break.
- **Explicit counter-trigger**: when NOT to use the wrapper and use the base directly.
- The wrapper also carries `learnings.md` and the clause. It does not inherit the base's learnings: each
  one records what broke at its own level.

## Workflows

### A) Creating a new skill

1. Pick an existing category (`workflow/`, `productivity/`, `software-development/`…).
   Do not invent new categories on a whim.
2. Look at 2 peer skills: `ls "$SKILLS_ROOT/<category>/"` and read one in full. Copy the register, not the
   content.
3. `skill_manage(action='create', name='...', category='<cat>', content=...)` — note: the
   `description` must fit in **60 chars** through this path.
4. Write `learnings.md` from `templates/learnings.md`.
5. Paste the clause from `templates/learnings-clause.md`.
6. Validate (next section) and **dogfood it**: use the skill at least once before declaring it
   good — including its own `learnings.md`, with the decisions you made while writing it.
7. **Fresh reviewer before "ready"**: dispatch a READ-ONLY subagent (`toolsets=['file']`) with
   the user's requirements numbered and the paths of all the skill's files; ask for
   PASS/FAIL per requirement, contradictions between `SKILL.md` / `references/` / `templates/`,
   non-executable instructions and data-loss risks. Whoever writes the artifact does not review it:
   they read what they meant to write.
8. **After the review, `diff` the artifact against its committed/published copy.** "READ-ONLY" is
   an instruction, not a lock: lines you did not write mean someone edited the live file, so read
   them, keep them only if correct, and fix what they reference wrongly. The file has no history of
   its own — without that diff there is no way to detect it.

### B) Modifying an existing skill

1. Open its `learnings.md` **before** editing. If there was already a failed attempt there, it is free.
2. Edit the live file (`patch` / `write_file`), never the snapshot copy.
3. If the change comes from a resolved error → new entry in `learnings.md` in the same turn.
4. If the change invalidates an old entry, **do not delete it**: mark `> ⚠️ superseded YYYY-MM-DD` and
   add the new one.
5. Re-validate frontmatter and sizes.

### C) Retrofitting existing skills to the standard

Never in a blind batch: there are hundreds of skills and a fraction is usually archived. Correct order:

```bash
# 1. who is missing what
python3 "$SKILLS_ROOT/<category>/skill-manager/scripts/audit-skills.py" --summary
# 2. detail for one subtree
python3 "$SKILLS_ROOT/<category>/skill-manager/scripts/audit-skills.py" --root "$SKILLS_ROOT/<category>"
```
1. **Lazy (default):** the retrofit is applied to the skill **being used**. It is the cheap mode and
   the one that breaks nothing: whoever touches the skill normalizes it.
2. **Batch per category:** pick one category, run the audit, apply to the `local` ones (not bundled,
   not hub), verify with the audit again.
3. **Bundled / hub → explicit opt-in.** Editing a bundled `SKILL.md` marks it user-modified and
   the harness's updater stops improving it. For bundled: by default **only** `learnings.md` is added; the
   clause needs the user's OK. Check the harness's modified-skills listing afterwards — do not assume an extra
   file leaves the skill "unmodified": the manifest stores a hash per skill that **does not** match the
   `SKILL.md` md5, so the exact rule cannot be deduced by eye.

### D) Publishing or exporting a skill

It goes to its own repo, with personal-data redaction and parity verification →
**`references/publication-export.md`**: export with `scripts/export-clean.sh`, gate with
`scripts/pii-scan.sh`, and why redacting the tree is not enough if the handle is in the history.

### E) Retiring, consolidating

Out of scope: deciding **which** skills should exist (curation and pruning) and operating your
installation's snapshot/deploy pipeline. This skill only leaves the artifact compliant.

## Validation (mandatory before saying "ready")

```bash
python3 - <<'PY'
import pathlib, re, yaml
p = pathlib.Path("$SKILLS_ROOT/<category>/<skill>/SKILL.md").expanduser()
c = p.read_text(encoding="utf-8")
assert c.startswith("---"), "does not start with ---"
m = re.search(r"\n---\s*\n", c[3:])
fm = yaml.safe_load(c[3:m.start()+3])
assert fm.get("name") and fm.get("description")
print(fm["name"], "desc", len(fm["description"]), "body", len(c), "chars")
assert len(fm["description"]) <= 1024
assert len(c) <= 20_000, ">20k: move detail to references/ (loader hard limit is 100k)"
PY
grep -qE '^##[[:space:]]+Learnings' "$SKILLS_ROOT/<category>/<skill>/SKILL.md"  # real heading, not a mention
ls "$SKILLS_ROOT/<category>/<skill>/learnings.md"
python3 "$SKILLS_ROOT/<category>/skill-manager/scripts/audit-skills.py" --show <skill>  # fml/lrn/cls ok
```

And the test that really matters: **would the skill load when it should?** Read the
`description` as if it were the only thing you will see (because it is the only thing seen): if it does not say
"Use when …" with a recognizable trigger, rewrite it.

## Learnings

This skill keeps `learnings.md` in its own directory (append-only).

- **Before improvising:** if something fails, blocks or comes out weird, search there first —
  `grep -in -A8 "<symptom>" "$SKILLS_ROOT/<category>/<skill>/learnings.md"`
  (or `skill_view('<skill>', file_path='learnings.md')`).
- **If you resolve it and it was not there:** record it in the same turn with
  `bash "$SKILLS_ROOT/<category>/skill-manager/scripts/append-learning.sh" <path-to-skill> --title "..." --symptom "..." --cause "..." --fix "..." --rule "..."`.
  One finding, one entry. Append-only **in the body**: prior text is never rewritten nor deleted; the
  only allowed mutation is appending a marker line (`⚠️ superseded` / `→ promoted`).
- **Promote to `## Common Pitfalls`?** Only if it meets **one** of these: the finding has already appeared
  twice, applies to **every** run of the skill, or is a safety/data precondition. If not,
  it stays in `learnings.md` — the body of `SKILL.md` is not a diary.
- Format, fields and size caps: `skill_view('skill-manager', file_path='references/learnings-standard.md')`.

> Literal copy of `templates/learnings-clause.md` — edit both together (the audit checks presence, not parity).

## Common Pitfalls

1. **Vague `description`** ("Helps with X"). Only the frontmatter enters the system prompt: a
   description without a trigger = invisible skill.
2. **`skill_manage` rejects descriptions over 60 chars when creating.** If you need more, write
   with `write_file` (installs the original) and verify the frontmatter by hand.
3. **Editing the snapshot copy.** The `rsync --delete` reverts it. The truth is local.
4. **Expecting to see the skill in the current session.** The loader is cached: fresh session.
5. **Retrofitting bundled without notice.** It pins the skill and cuts its upstream updates.
6. **Binary junk in the skill directory** (browser profile, `.db`, `.zip`, screenshots): the
   snapshot publishes whatever is there. `rsync` excludes `chrome-*profile/`, **not** `.db` or
   binaries, and the secret masker reads only UTF-8 (`except UnicodeDecodeError: continue`), so a
   blob passes unmasked. If an artifact must not leave the host, it does not live inside the skill.
7. **Duplicating content in a wrapper** instead of referencing: two sources of truth, they diverge.
8. **Learnings as a diary.** It is not a session log: one entry = one finding that saves time
   next time. If it does not save time, it does not go in.
9. **Writing the skill in the chat's language.** The artifact is shared and published: it goes in
   English even if the conversation is in Spanish. You translate the file, not the chat.
10. **Promoting everything to `SKILL.md`.** The body grows until nobody reads it. Stable and universal →
   pitfall; specific and rare → it stays in `learnings.md`.
11. **Counting skills with `find -maxdepth N`.** It undercounts (skills nest up to 4 levels).
    Measure with `audit-skills.py --summary`.
12. **Validating the clause with `grep learnings.md`.** A skill that only *mentions* the file passes
    that grep. The clause exists when there is a `## Learnings` heading; the audit uses a heading
    regex.
13. **An exporter that swallows `stderr` gives false clean results.** If the redaction map is applied with
    `sed -i ... 2>/dev/null`, a badly escaped rule (typical case: the term contains the delimiter
    `|`) fails and reads as "applied"; the gate in the next step checks the result, but if you
    also silence it there, you publish with the term inside. Escape the delimiter, do not silence
    `stderr` and order the map from most specific to most general (otherwise a generic rule rewrites the
    text the specific one was going to fix).

## Verification Checklist

- [ ] Frontmatter: starts with `---`, `name` + `description` present, description ≤60 (or ≤1024
      via write_file).
- [ ] Description with `Use when …` and a recognizable trigger.
- [ ] `learnings.md` exists and has a header with the append-only rule.
- [ ] `## Learnings` present in the `SKILL.md` with the 4 instructions (consult / record /
      promote / format).
- [ ] `## Common Pitfalls` with at least one real error, not a generic one.
- [ ] Size within range; detail moved to `references/`.
- [ ] the harness's skill list sees it (fresh process).
- [ ] If it is bundled: it was asked before touching its `SKILL.md`.

## References

- `references/publication-export.md` — export to your own repo: order, redaction, gate, and how to
  purge content that already reached `refs/pull/*`.
- `references/script-hygiene.md` — the scripts a skill ships: argument loops, exit codes, gates vs
  warnings, and the test matrix (installed layout + flat copy).
- `references/harness-agnostic.md` — writing a skill for any harness: one anchor for paths,
  capabilities instead of command names, root derivation that fails fast.
- `references/learnings-standard.md` — full learnings spec: fields, caps, promotion, retrofit matrix.
- `templates/learnings-clause.md` — the canonical `## Learnings` block (copy as is).
- `templates/learnings.md` — initial header of the learnings file.
- `scripts/append-learning.sh` — atomic append; creates the header **from `templates/learnings.md`**,
  rejects `.archive`/`.hub`/`snapshots` paths, flattens newlines, needs `--title` + one content field.
- `scripts/pii-scan.sh` — gate over tree, history, authors, owner, PR refs
  (list at `<root>/../references/pii-blocklist.txt`).
- `scripts/export-clean.sh` — copy + redaction map; aborts on any surviving forbidden term.
- `scripts/audit-skills.py` — gap audit by origin: YAML frontmatter, clause in 3 levels, and
  `--fail-on-gaps` counting only live skills.
- `learnings.md` — what this skill itself learned. Read it before fighting the loader. **Local only:**
  exports carry the header (append-only rules) with zero entries.
