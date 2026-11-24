# Learnings Standard — full specification

Single source of the rules for `learnings.md`. The clause pasted into each `SKILL.md` is the
short summary (`templates/learnings-clause.md`); **this file holds the detail** and is cited from
there, so the text isn't duplicated across hundreds of skills.

## 1. What it is

`learnings.md` is a skill's self-learning channel: an append-only file, in the same
directory as `SKILL.md`, where the agent records the **non-obvious** findings from having used the
skill. It is not a changelog, not a session journal, not domain documentation.

Filter question before writing: **does this finding save the next agent that
runs this skill some time?** If not, it doesn't go in.

## 2. Location

```
$SKILLS_ROOT/<category>/<skill>/
├── SKILL.md          # with the ## Learnings clause
├── learnings.md      # this standard
├── references/       # long detail (optional)
├── templates/        # templates (optional)
└── scripts/          # utilities (optional)
```

One `learnings.md` per skill. Wrapper skills **do not** share the base skill's
file: each level records what broke at its own level.

## 3. Entry format

```markdown
## YYYY-MM-DD — <short, searchable title>

- **Context:** what was being done when it appeared.
- **Symptom:** the exact error, the literal output, the observed behavior.
- **Cause:** why it happened (not "X failed", but the mechanism).
- **Fix:** the concrete command / patch / change that resolved it.
- **Rule:** the imperative line that keeps it from happening again.
```

Format rules:

| Field | Required | Note |
|---|---|---|
| Title | yes | Searchable with `grep`. Include the error literal if there is one. |
| Context | no | Only if the symptom is unintelligible without it. |
| Symptom | yes | Literal. Future `grep` depends on these words. |
| Cause | yes | The mechanism, not the symptom restated. |
| Fix | yes | Exact command, not a vague description. |
| Rule | yes | Imperative, no dates, no PR numbers, no narrating the incident. |

**No session traces:** nothing like "the user told me that…", people's names, or conversation
IDs. A learning is read years later, out of context.

## 4. Lifecycle

```
       ┌──────────── failure / blockage / odd result
       ▼
 1. GREP learnings.md  ──found?──► yes ──► apply recorded fix ──► end
       │ no
       ▼
 2. resolve it (investigate, test, read code)
       ▼
 3. APPEND new entry (scripts/append-learning.sh)
       ▼
 4. does it apply to every future run? ── yes ──► promote to ## Common Pitfalls
       │                                        (the entry stays as backup)
       ▼ no
 5. it stays in learnings.md as a concrete case
```

**Write obligation:** if the agent resolved something that cost it more than ~5 minutes, researched
external sources, or hit an undocumented error, **record it in the same turn**. Do not leave it
"for later": the next session doesn't have the context.

## 5. Promotion to `## Common Pitfalls`

Promote when any of the following holds:

- The same finding has already appeared twice in `learnings.md` (or in two different skills).
- It applies to **every** run of the skill, not to one particular configuration.
- It is a safety or data precondition (not "it sometimes fails").

Do not promote when:

- It depends on a binary version or on a specific host → it stays in `learnings.md`.
- It is a workaround that expires (temporary password, downed endpoint) → `learnings.md` with a date.

When promoting, **do not delete** the entry: append the marker line
`→ promoted to ## Common Pitfalls (YYYY-MM-DD)` at the end. It is the only authorized mutation on a past
entry (along with `⚠️ superseded YYYY-MM-DD`); rewriting the body is not allowed.

## 6. Size cap and pruning

- `learnings.md` ≤ **200 lines** / ~15 KB. It is a file read with `grep`, not a corpus.
- When past the cap: group the already promoted entries into a
  `## Promovidos (histórico)` section and keep the 10–15 live entries at the top.
- Never delete or rewrite: if compaction is needed, group by section with markers; don't
  remove or "improve" the text of an old entry.
- `learnings.md` counts toward the skill's budget: if `SKILL.md` is already at 20k, stable
  detail goes to `references/`, not to `learnings.md`.

## 7. What does NOT go in learnings.md

- **Secrets, tokens, cookies, paths with credentials.** Not in the symptom and not in the fix: write
  `the <service> token had expired`, never the value.
- **Personal data** of third parties (patients, client names) — use roles.
- **Conversation logs** or transcripts.
- **Design decisions** that belong in the `SKILL.md` or in a `references/`: if it is
  stable, it is documentation, not a learning.
- **Data that expires with no date**: a price, a schedule, an API status. If it goes in, it goes with a date and
  with "verify before use".

## 8. Examples

**Good** (actionable, with a searchable literal):

```markdown
## 2026-11-23 — `403 Forbidden` when reading the Chrome profile over CDP

- **Symptom:** `CDP error 403` when calling `Network.getAllCookies` on an open profile.
- **Cause:** Chrome launched without `--remote-debugging-port` but with `--remote-debugging-pipe`;
  the HTTP endpoint listens on the pipe socket, not on a TCP port.
- **Fix:** add `--remote-debugging-port=9222` at launch and wait for
  `curl -s localhost:9222/json/version` before connecting.
- **Rule:** verify `/json/version` before any CDP call; if it fails, do not retry in a
  loop, relaunch the browser with the flag.
```

**Bad** (narrative, not actionable):

```markdown
## 2026-11-23 — Problems with the browser
- I spent a while fighting Chrome and in the end it worked.
- Rule: be careful.
```

## 9. Retrofit matrix by origin

| Origin | How it is detected | `learnings.md` | Clause in `SKILL.md` |
|---|---|---|---|
| `local` (agent-created, author: skill owner) | not listed in `.bundled_manifest` | create without asking | add without asking |
| `bundled` | name listed in `.bundled_manifest` (`nombre:hash` per skill) | create without asking (new file) | **only with an explicit OK**: editing it marks it user-modified and the harness's updater stops bringing it upstream improvements |
| `hub` | under `.hub/` | do not touch | do not touch |
| archived | under `.archive/` | do not touch (lost work) | do not touch |

Verification after writing to a bundled skill:
the harness's modified-skills listing — if the skill shows up, the edit is now "pinned" and the user has to be
told.

## 10. Audit

`scripts/audit-skills.py` computes the real state:

```bash
python3 scripts/audit-skills.py --summary                      # total / alive / live gaps
python3 scripts/audit-skills.py --root "$SKILLS_ROOT/<category>"  # a subtree
python3 scripts/audit-skills.py --json | jq -r '.skills[] | select(.clause != "full") | .name'
python3 scripts/audit-skills.py --fail-on-gaps                 # CI / cron: exit 1 if there are LIVE gaps
```

**Archived skills do not count as a gap.** The gate evaluates only live skills (it excludes `.archive/` and
`.hub/`): if there are archived skills (`.archive/`), a gate that includes them always returns exit 1 and is
useless. `--summary` prints `skills: N · live: M · without gaps` so the difference is visible.

Each record reports: `path`, `name`, `origin` (`local|bundled|hub|archived`), `frontmatter`
(real YAML via `safe_load`, not regex), `learnings` (bool), `clause` (`full` | `partial` | `none`),
`description_chars` and `chars`. `full` requires that the `## Learnings` section name `learnings.md` and
the query/record command: an empty heading stays at `partial` and counts as a gap.
