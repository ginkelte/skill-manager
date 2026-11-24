# Splitting an oversized `SKILL.md`

A whole-file rewrite is the most dangerous edit a skill can get. This is the procedure.
The loader hard-rejects past ~100k and the standard wants detail out of the body well before that. The
split is a **whole-file rewrite**, which makes it the most dangerous edit you can make to a skill: get
it wrong and the body is silently truncated while still looking like a valid file.

1. **Back up, and know the only recovery path.** A skill has no history of its own — the one copy that
exists elsewhere is the snapshot in the backup repo:
   ```bash
   git -C <backup-repo> show origin/main:<snapshot-path>/<category>/<skill>/SKILL.md \
     > /tmp/<skill>.bak
   stat -c %s /tmp/<skill>.bak   # must equal the live size, else the snapshot is older than the file
   ```
   `.curator_backups/` is **not** a reliable restore point: it is periodic, and a skill edited after
   the last backup has no copy there.
2. **Extract fence-aware.** A heading only counts when it is **outside** a code fence. The naive
   `^#{1,6} ` regex also matches `# 1. List all crons` comments *inside* fenced blocks, so the section
   ends at the first such line: the heading gets replaced by the pointer while the rest of the body
   stays below it — orphaned content and a broken fence.
   ```python
   heads, in_fence = [], False
   for i, l in enumerate(lines):
       if l.lstrip().startswith("```"):
           in_fence = not in_fence
           continue
       if not in_fence and re.match(r"^#{2,4} \S", l):
           heads.append(i)
   ```
3. **Verify all four, not just the size:** every moved block is a substring of its `references/` file;
   the fence count is even; the pointer sits *immediately before the next heading*; and the new size is
   under the limit with margin.
4. **Write pointers, not summaries.** `> Detail moved to [references/<topic>.md](…) — full original
   content there.` A paraphrased pointer is a second source of truth that drifts.
