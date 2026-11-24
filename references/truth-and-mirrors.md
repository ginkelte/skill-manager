# Where a skill's truth lives

The single most useful check before touching a skill: find out which copy is authoritative in
this installation, and whether something else mirrors it.

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
