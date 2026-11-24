# Writing a skill for any harness

A skill that names its origin is a personal note; a skill that names the *capability* is an
artifact anyone can adopt. Use this when a skill will be shared, published or reused outside the
installation it was written in — and when generalizing one that already leaked its origin.

## The two rules

1. **One anchor for paths.** Never bake an absolute path. Express every location as
   `$SKILLS_ROOT/<category>/<skill>/...` and say once, at the top, what `$SKILLS_ROOT` means.
2. **Capability, not command name.** Prose says what has to happen ("the harness's skill list",
   "the harness's updater"); the concrete command appears only as an example. A reader on another
   harness then knows what to look for instead of what to type.

Apply the same treatment to: frontmatter (keep only universal fields, mention the
`metadata.<harness>` namespace as optional), optional infrastructure (a manifest, a snapshot job,
"bundled" or "pinned" behaviour — describe them as things your setup *may* have), and any private
vocabulary (term lists, redaction maps, account names) that must live **outside** the artifact.

## Scripts must derive their own root, and fail fast

Deriving a path by counting `..` from the script is fine only if the result is validated. A plain
clone of the artifact has no `<category>/<skill>/` layout at all, so the same expression that
resolves correctly in the installed tree lands on `/tmp` or `/` — and a recursive discovery over
that root crawls the filesystem instead of returning.

```python
_SCRIPT_DIR = Path(__file__).resolve().parent
REJECTED_ROOTS = {Path("/").resolve(), Path("/tmp").resolve(), Path("/var/tmp").resolve(),
                  Path.home().resolve()}

def looks_like_root(p: Path) -> bool:
    """True if `p` holds skills directly or one category deep."""
    return any(p.glob("*/SKILL.md")) or any(p.glob("*/*/SKILL.md"))
```

Rules that follow from it:

- **Reject before you glob.** Test the candidate against the rejected set *first*: probing `/` is
  what turns a wrong guess into a crawl.
- **Bound the walk.** Glob a fixed depth (`*/*/*/SKILL.md`) instead of `rglob`; a wrong root then
  costs milliseconds.
- **Fail with the fix, not with a traceback.** `exit 2` and the sentence "pass `--root <dir>` or set
  `$SKILLS_ROOT`".
- **Search order for external files:** explicit env var → `<root>/../references/...` → the script's
  own `../references/...`, first one that exists. Name the path to create when none does.
- **`$SKILLS_ROOT` overrides the derivation** everywhere, so a user with an unusual layout is never
  blocked.

## Verification: test it in two contexts

Run each script twice — from the installed layout and from a flat copy (a `git clone` of the
artifact, no categories) — and check three things:

```bash
# 1. the product name is gone from the artifact
grep -rin '<product>' "$SKILLS_ROOT/<category>/<skill>" --exclude-dir=.git   # → 0 hits
# 2. installed layout: derived root is the skills root
python3 scripts/<script>.py --summary
# 3. flat copy: exits 2 immediately with the instruction, never hangs
cd /tmp/flat && timeout 20 python3 scripts/<script>.py --summary; echo $?
```

A generalization is not done when the words are replaced; it is done when the scripts still work
in the unusual layout and say what to do when they cannot.

## Pitfalls

- **Renaming the product but keeping its layout.** Paths like `~/.<product>/skills` and commands like
  `<product> skills list` are the same dependence as the name. Replace the *assumption*, not the
  string.
- **Leaving the product's own CLI in the verification steps.** "Verify with `<product> update`" is
  useless to anyone else; describe the check ("the harness's modified-skills listing, if it has one").
- **Shipping the private vocabulary.** A term list or redaction map inside the artifact makes the
  artifact the leak. Document where it lives; do not include it.
- **Trusting a derived root because it worked once.** The installed tree hides the bug: the flat
  clone is the test that exposes it.
- **Claiming generality in the title while the body still says "your installation".** Sweep the whole
  artifact — `SKILL.md`, `references/`, `templates/`, script comments and messages — and re-grep after
  every edit, because a translator or a later patch can reintroduce the name.
