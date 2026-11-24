# Learnings — <skill-name>

> Append-only **in the body**: one entry per **non-obvious** finding — what had to be researched,
> the error that cost time, the constraint nobody had documented, the workaround that worked.
>
> - Previous text is never rewritten or deleted. The **only** allowed mutation is adding a marker
>   line (`⚠️ superseded YYYY-MM-DD` / `→ promoted` to `## Common Pitfalls`) at the end of an existing
>   entry.
> - Do not duplicate `SKILL.md`: if the lesson meets the promotion criteria, move it up to
>   `## Common Pitfalls` and leave the concrete case here.
> - One finding, one entry. If it won't save time next time, it doesn't belong.
>
> Record: `bash "$SKILLS_ROOT/<category>/skill-manager/scripts/append-learning.sh" <path-to-skill> --title "..."`
