# Publishing and exporting a skill

Full procedure for the export, personal-data redaction, and parity
verification. It was split out of `SKILL.md` because it is the longest block and the one that runs
least often (once per skill, not per session).

---

## E) Publishing a skill to your own repo (export)

**Hard rule:** the originals under `$SKILLS_ROOT/` are **not touched** in order to publish. A copy is
exported, and at the end you verify that the original stayed byte-identical.

```bash
S=$SKILLS_ROOT/<category>/skill-manager        # original (untouchable)
T=~/git/skill-manager                          # export (own repo)

# 1. fingerprint of the original
find "$S" -type f -exec md5sum {} \; | sort -k2 > /tmp/orig.md5

# 2. copy, and git BEFORE writing anything else
mkdir -p "$T"
cp -a "$S"/{SKILL.md,learnings.md,references,templates,scripts} "$T"/
cd "$T"
git init -b main && git remote add origin <url>
git fetch origin main && git reset --hard origin/main   # ⚠️ OVERWRITES files already written
git checkout -b feat/<algo>

# 3. only now README/LICENSE/.gitignore
git add -A && git commit -m "feat: <skill>" && git push -u origin feat/<algo>
gh pr create --base main --head feat/<algo> --title "..." --body "..."
gh pr merge --squash --delete-branch

# 4. verify on the remote AND that the original did not change
gh api repos/<owner>/<repo>/git/trees/main?recursive=1 --jq '.tree[] | "\(.size)\t\(.path)"'
find "$S" -type f -exec md5sum {} \; | sort -k2 | diff - /tmp/orig.md5 && echo "original intacto"
```

🚨 **`git reset --hard origin/main` deletes what you already wrote in the directory.** If the repo was
created with `--add-readme`, GitHub's tracked `README.md` overwrites yours (untracked files
survive). Measured: a 4.016-byte README was reduced to the 99-byte stub and the PR came out
green with the wrong README. Correct order: `init` + `fetch` + `reset` **first**, write
files **after**. And the verification that matters is the remote one (`git/trees/main?recursive=1`),
not the local commit.

**The export is re-synced in the same change as the live skill.** If you edit
`$SKILLS_ROOT/<category>/<skill>/...` and don't copy to the repo again, the published repo starts lying
and nobody notices: the only symptom is that a file in the repo has a different size. Parity
verification, file by file:

```bash
S=$SKILLS_ROOT/<category>/skill-manager; T=~/git/skill-manager
for f in SKILL.md learnings.md references/*.md templates/*.md scripts/*; do
  cmp -s "$S/${f#*/}" "$T/${f#*/}" 2>/dev/null || echo "DRIFT $f"
done
diff <(git -C "$T" show origin/main:SKILL.md) "$S/SKILL.md" >/dev/null && echo "repo == live"
```

**The export branch comes off `origin/main`, never off the PR's previous branch.** After a squash
merge, chaining the new branch onto the old one leaves the PR unmergeable even when the diff is just two
files. The measured case and its recovery (`reset --hard origin/main` + `cherry-pick` +
`push --force-with-lease`) are in this skill's `learnings.md`, entry «PR stacked on a branch
already merged by squash».

## F) Publishing: personal-data filter (mandatory)

Nothing public carries the account handle, the author's alias, or the name of the private infrastructure.
Before publishing, the export goes through a filter and a gate:

```bash
bash scripts/export-clean.sh "$SKILLS_ROOT/<category>/<skill>" ~/git/<repo> --force  # copy + redact
bash scripts/pii-scan.sh ~/git/<repo>                                              # gate: tree + history + owner + refs
```

- The list of forbidden terms lives in `<root>/../references/pii-blocklist.txt` and the replacement map
  in `<root>/../references/pii-export-map.txt` — **both private, outside the skill**.
  If they lived inside it, the published skill would be the leak.
- `export-clean.sh` aborts if the tree still has hits. "Publishing with a pending hit" does not exist.
- **The tree is not everything.** If the handle is already in the commits, in the remote URL, or in
  `refs/pull/*/head`, redacting files is not enough: the way out is a new repo (or a neutral
  account) with a single clean commit. `pii-scan.sh` reports the three things separately and
  `--tree-only` is useful to verify only the working tree while iterating.
- **The export is not a literal copy of the skill** (by design). Parity is verified against the
  filter's output, not against the live file:
  `bash scripts/export-clean.sh <skill> /tmp/exp --force && diff -r /tmp/exp ~/git/<repo>`.

### `learnings.md` never ships with content

`learnings.md` is session memory: what the agent learned while working on **that** host. In the
public artifact it ships with **only the canonical header** — the append-only rules, the promotion
rule and the recording command, which are useful documentation — and **zero entries**.

- `export-clean.sh` regenerates it from `templates/learnings.md` (the `<skill-name>` placeholder
  filled with the real name) and **aborts** if any `## YYYY-MM-DD` entry or more than 2 KB
  survives: it is a gate, not a convention.
- The real file lives in `$SKILLS_ROOT/<category>/<skill>/learnings.md` and never leaves there.
- If content was ever published, redacting the tree is **not enough**: the blob stays in history
  and in every PR head ref. Purge and verify:

  ```bash
  # a force-push does NOT touch PR refs: they are not branches
  git ls-remote origin 'refs/pull/*/head'
  for r in $(git ls-remote origin 'refs/pull/*/head' | awk '{print $2}'); do
    git fetch -q origin "$r:refs/tmp/$(basename "$r")"
    git cat-file -s "refs/tmp/$(basename "$r"):learnings.md"   # must be the header size, never more
  done
  git log --all --format=%H -- learnings.md | while read -h; do :; done  # one version, header only
  ```

  Sealing order, cheapest that works first: delete the repo (needs the `delete_repo` scope) →
  rename it and flip it to **private** (the refs stop being public, and the content stays
  recoverable) → a new public repo with one commit and no PRs. Never leave the old one public
  "because main is clean": main was never the leak.
- **0 bytes teaches nothing.** When the published file's value is its *rules* (an append-only
  contract, a schema, a format), ship the canonical header with zero records — not an empty file.
  Regenerate it from the template at export time and make the gate abort on any record.

### Publishing from a personal account

There are two distinct layers and it is best not to confuse them:

| Layer | Rule |
|---|---|
| **Content** (files, published repo history, PRs) | Zero personal identifiers. Verified with `pii-scan.sh --tree-only` and with a **new** repo with a single commit if the origin has dirty history. |
| **Owning account** | Publishing from a personal account means the *owner* and the initial commit's author are that handle. It is the owner's decision, not an oversight: the gate reports it and it is accepted explicitly. |

When the owner chooses to publish from their account, the procedure is: a **new** repo (not the one with
history), a single commit with a neutral author (`<proyecto> maintainers`) and **no** signing with a
personal key — that way the content and the messages stay clean and the only fingerprint is the account, which is
public by choice.
