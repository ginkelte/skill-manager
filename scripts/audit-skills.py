#!/usr/bin/env python3
"""Audit skills against the skill-manager standard.

Reports, per skill: origin (local/bundled/hub/archived), valid frontmatter (real
YAML, not regex), presence of `learnings.md`, level of the learnings clause
(`full` / `partial` / `none`) and SKILL.md size.

Usage:
    audit-skills.py                      # every skill under the default root
    audit-skills.py --root <dir>         # subtree
    audit-skills.py --summary            # counts only
    audit-skills.py --json               # machine-readable
    audit-skills.py --fail-on-gaps       # exit 1 if there are gaps in LIVE skills
    audit-skills.py --show <name>        # detail for a single skill

Archived skills (`.archive/`) and hub skills (`.hub/`) are reported but do **not**
count as a gap: the standard forbids touching them, so a gate that includes them
always fails and is useless.

Exit codes: 0 = ok (or no --fail-on-gaps), 1 = gaps in live skills with
--fail-on-gaps, 2 = usage/input error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - explicit degradation
    yaml = None

# Root resolution, in order: --root, $SKILLS_ROOT, this file's location
# (scripts/ -> skill -> category -> root), then ~/skills. A candidate only counts if it
# actually looks like a skills root — otherwise the script could scan an unrelated tree.
_SCRIPT_DIR = Path(__file__).resolve().parent
# Roots a wrong derivation can land on; globbing them would crawl the filesystem.
REJECTED_ROOTS = {
    Path("/").resolve(),
    Path("/tmp").resolve(),
    Path("/var/tmp").resolve(),
    Path.home().resolve(),
}


def looks_like_root(p: Path) -> bool:
    """True if `p` holds skills directly or one category deep (`*/SKILL.md`, `*/*/SKILL.md`)."""
    try:
        return any(p.glob("*/SKILL.md")) or any(p.glob("*/*/SKILL.md"))
    except OSError:
        return False


def resolve_root() -> Path:
    """First candidate that looks like a skills root; `~/skills` when none does.

    Rejected roots are skipped before any glob: probing them is what turns a wrong
    guess into a filesystem crawl.
    """
    candidates = [os.environ.get("SKILLS_ROOT"), _SCRIPT_DIR.parents[2], Path.home() / "skills"]
    for c in candidates:
        if not c:
            continue
        p = Path(c).expanduser()
        if p.resolve() in REJECTED_ROOTS:
            continue
        if looks_like_root(p):
            return p
    return Path.home() / "skills"


DEFAULT_ROOT = resolve_root()
MANIFEST = DEFAULT_ROOT / ".bundled_manifest"

FRONTMATTER_RE = re.compile(r"\n---\s*\n")
NON_WRITABLE_ORIGINS = ("archived", "hub")


def load_manifest() -> set[str]:
    """Return the names listed in .bundled_manifest (format `name:hash`)."""
    names: set[str] = set()
    if MANIFEST.is_file():
        for line in MANIFEST.read_text(encoding="utf-8", errors="replace").splitlines():
            if ":" in line:
                names.add(line.rsplit(":", 1)[0].strip())
    return names


def parse_frontmatter(text: str) -> tuple[dict[str, str], bool, int]:
    """Parse the frontmatter with real YAML.

    Returns:
        (fields, valid, offset): `fields` carries `name`/`description` already
        unfolded (in case they came as a block scalar), `valid` requires parseable
        YAML plus both keys, `offset` is the index where the body starts.

    `yaml.safe_load` is used because a regex returns the `>-` indicator instead of
    the text and does not detect invalid YAML (unclosed quote, broken indentation).
    """
    if not text.startswith("---"):
        return {}, False, 0
    m = FRONTMATTER_RE.search(text[3:])
    if not m:
        return {}, False, 0
    block = text[3 : m.start() + 3]
    end = 3 + m.end()

    fields: dict[str, str] = {}
    valid = False
    if yaml is not None:
        try:
            data = yaml.safe_load(block)
        except Exception:
            data = None
        if isinstance(data, dict):
            valid = True
            for key in ("name", "description"):
                value = data.get(key)
                if isinstance(value, str) and value.strip():
                    fields[key] = value.strip()

    if not fields:  # fallback: no PyYAML or unreadable YAML
        for key in ("name", "description"):
            km = re.search(rf"^{key}\s*:\s*(.+)$", block, re.MULTILINE)
            if km:
                fields[key] = km.group(1).strip().strip('"').strip("'")
        # Without PyYAML a regex cannot prove the YAML is valid, but it can prove the keys
        # exist — reporting every skill as BAD would be a worse lie than a weaker check.
        if yaml is None and fields.get("name") and fields.get("description"):
            valid = True

    return fields, bool(valid and fields.get("name") and fields.get("description")), end


def classify(path: Path, manifest: set[str]) -> str:
    """Skill origin based on its location and the bundled manifest."""
    parts = path.parts
    if ".archive" in parts:
        return "archived"
    if ".hub" in parts:
        return "hub"
    if path.parent.name in manifest:
        return "bundled"
    return "local"


def clause_level(body: str) -> str:
    """Clause level: `full`, `partial` or `none`.

    `full` requires the `## Learnings` section to declare the file and how to
    consult/record it. An empty heading does not meet the standard: that is why
    searching for the title alone is not enough.
    """
    m = re.search(r"^##\s+Learnings\s*$", body, re.MULTILINE)
    if not m:
        return "none"
    rest = body[m.end() :]
    nxt = re.search(r"^##\s+", rest, re.MULTILINE)
    section = rest[: nxt.start()] if nxt else rest
    has_file = "learnings.md" in section
    has_how = "append-learning.sh" in section or "skill_view(" in section
    return "full" if (has_file and has_how) else "partial"


def audit_skill(skill_md: Path, manifest: set[str]) -> dict:
    """Build the audit record for a single SKILL.md."""
    text = skill_md.read_text(encoding="utf-8", errors="replace")
    fields, fm_ok, offset = parse_frontmatter(text)
    body = text[offset:] if offset else text
    skill_dir = skill_md.parent
    clause = clause_level(body)
    return {
        "path": str(skill_dir),
        "name": fields.get("name") or skill_dir.name,
        "origin": classify(skill_dir, manifest),
        "frontmatter": fm_ok,
        "learnings": (skill_dir / "learnings.md").is_file(),
        "clause": clause,
        "clause_ok": clause == "full",
        "chars": len(text),
        "description_chars": len(fields.get("description", "")),
    }


MAX_DEPTH = 4


def discover(root: Path) -> list[Path]:
    """Every SKILL.md under root, up to MAX_DEPTH levels, sorted.

    Depth is bounded on purpose: a wrong root (a tmp dir, a home dir) must fail fast
    instead of walking the filesystem. Curator copies (`.curator_backups`) are not
    live skills and are excluded.
    """
    found: list[Path] = []
    for depth in range(1, MAX_DEPTH + 1):
        found.extend(root.glob("/".join(["*"] * depth + ["SKILL.md"])))
    return sorted(p for p in found if ".curator_backups" not in p.parts)


def has_gap(record: dict) -> bool:
    """Does this skill violate the standard? Archived and hub skills never count."""
    if record["origin"] in NON_WRITABLE_ORIGINS:
        return False
    return not (record["frontmatter"] and record["learnings"] and record["clause_ok"])


def main(argv: list[str]) -> int:
    """Entrypoint: walk the skills and report gaps."""
    ap = argparse.ArgumentParser(description="Audit skills against the skill-manager standard.")
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--fail-on-gaps", action="store_true")
    ap.add_argument("--show", metavar="NAME")
    args = ap.parse_args(argv)

    if not args.root.is_dir():
        print(f"error: {args.root} does not exist — pass --root <dir> or set $SKILLS_ROOT",
              file=sys.stderr)
        return 2
    if args.root.resolve() in REJECTED_ROOTS:
        print(
            f"error: {args.root} is not a skills root — pass --root <dir> or set $SKILLS_ROOT",
            file=sys.stderr,
        )
        return 2
    if yaml is None:
        print("warning: PyYAML missing — frontmatter validated by regex (less reliable)", file=sys.stderr)

    manifest = load_manifest()
    records = [audit_skill(p, manifest) for p in discover(args.root)]
    if args.show:
        records = [r for r in records if r["name"] == args.show or Path(r["path"]).name == args.show]
        if not records:
            print(f"error: skill {args.show!r} not found under {args.root}", file=sys.stderr)
            return 2

    live = [r for r in records if r["origin"] not in NON_WRITABLE_ORIGINS]
    gaps = [r for r in records if has_gap(r)]
    by_origin: dict[str, int] = {}
    for r in records:
        by_origin[r["origin"]] = by_origin.get(r["origin"], 0) + 1

    if args.json:
        print(json.dumps({
            "root": str(args.root),
            "total": len(records),
            "live": len(live),
            "with_gaps": len(gaps),
            "gap_names": sorted(r["name"] for r in gaps),
            "by_origin": by_origin,
            "missing_learnings": sum(1 for r in live if not r["learnings"]),
            "missing_clause": sum(1 for r in live if not r["clause_ok"]),
            "bad_frontmatter": sum(1 for r in live if not r["frontmatter"]),
            "skills": records,
        }, indent=2, ensure_ascii=False))
    elif args.summary:
        print(f"root: {args.root}")
        print(f"skills: {len(records)}  ·  live: {len(live)}  ·  without gaps: {len(live) - len(gaps)}")
        print("origin: " + "  ".join(f"{k}={v}" for k, v in sorted(by_origin.items())))
        print(f"gaps (live):        {len(gaps)}")
        print(f"no learnings.md:    {sum(1 for r in live if not r['learnings'])}")
        print(f"no clause:          {sum(1 for r in live if not r['clause_ok'])}")
        print(f"broken frontmatter: {sum(1 for r in live if not r['frontmatter'])}")
    else:
        print(f"{'origin':9} {'fml':4} {'lrn':4} {'clause':9} {'chars':>6}  skill")
        for r in records:
            cls = {"full": "ok", "partial": "partial", "none": "--"}[r["clause"]]
            print(
                f"{r['origin']:9} {'ok' if r['frontmatter'] else 'BAD':4} "
                f"{'ok' if r['learnings'] else '--':4} {cls:9} "
                f"{r['chars']:6}  {r['name']}"
            )
        print(f"\ntotal {len(records)} · live {len(live)} · gaps {len(gaps)}")

    return 1 if (args.fail_on_gaps and gaps) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
