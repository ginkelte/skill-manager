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
