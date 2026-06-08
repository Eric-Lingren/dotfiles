#!/usr/bin/env python3
from __future__ import annotations

"""
Migrate skill SKILL.md files to use shared tail-block references.

Replaces inline <!-- learning-capture:start/end --> blocks with a 4-line stub
that references resources/learning-capture.md. Preserves any "What's next"
content found between <!-- skill-done: slug --> and <!-- learning-capture:end -->.

Replaces inline <!-- attribution-capture:start/end --> blocks with a 3-line stub
that references resources/attribution-capture.md.

Usage:
    python3 migrate-skill-tail-blocks.py [--dry-run]
"""

import re
import sys
from pathlib import Path

SKILLS_DIR = Path(__file__).parent.parent / "skills"
DRY_RUN = "--dry-run" in sys.argv

LEARNING_CAPTURE_STUB = """\
<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `{slug}`.
<!-- skill-done: {slug} -->{whats_next}
<!-- learning-capture:end -->"""

ATTRIBUTION_CAPTURE_STUB = """\
<!-- attribution-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/attribution-capture.md`.
<!-- attribution-capture:end -->"""

LEARNING_BLOCK_RE = re.compile(
    r"<!-- learning-capture:start -->.*?<!-- learning-capture:end -->",
    re.DOTALL,
)

SKILL_DONE_RE = re.compile(r"<!-- skill-done: ([a-z0-9_-]+) -->")

WHATS_NEXT_RE = re.compile(
    r"<!-- skill-done: [a-z0-9_-]+ -->(.*?)<!-- learning-capture:end -->",
    re.DOTALL,
)

ATTRIBUTION_BLOCK_RE = re.compile(
    r"<!-- attribution-capture:start -->.*?<!-- attribution-capture:end -->",
    re.DOTALL,
)


def log(msg: str) -> None:
    sys.stdout.write(msg + "\n")  # noqa: T201


def migrate_file(path: Path) -> bool:
    original = path.read_text()
    content = original

    lc_match = LEARNING_BLOCK_RE.search(content)
    if lc_match:
        block = lc_match.group(0)
        slug_match = SKILL_DONE_RE.search(block)
        if not slug_match:
            log(f"  SKIP (no skill-done slug): {path}")
        else:
            slug = slug_match.group(1)
            whats_next_match = WHATS_NEXT_RE.search(block)
            whats_next_body = whats_next_match.group(1) if whats_next_match else ""
            whats_next = whats_next_body.rstrip() if whats_next_body.strip() else ""
            if whats_next and not whats_next.startswith("\n"):
                whats_next = "\n" + whats_next
            stub = LEARNING_CAPTURE_STUB.format(slug=slug, whats_next=whats_next)
            content = content[: lc_match.start()] + stub + content[lc_match.end() :]

    ac_match = ATTRIBUTION_BLOCK_RE.search(content)
    if ac_match:
        content = content[: ac_match.start()] + ATTRIBUTION_CAPTURE_STUB + content[ac_match.end() :]

    if content == original:
        return False

    if DRY_RUN:
        log(f"  [dry-run] would update: {path.relative_to(SKILLS_DIR.parent)}")
    else:
        path.write_text(content)
        log(f"  updated: {path.relative_to(SKILLS_DIR.parent)}")
    return True


def main() -> None:
    skill_files = sorted(SKILLS_DIR.glob("*/SKILL.md"))
    if not skill_files:
        log(f"No SKILL.md files found under {SKILLS_DIR}")
        sys.exit(1)

    changed = 0
    for f in skill_files:
        if migrate_file(f):
            changed += 1

    prefix = "[dry-run] " if DRY_RUN else ""
    log(f"\n{prefix}Done. {changed}/{len(skill_files)} files updated.")


if __name__ == "__main__":
    main()
