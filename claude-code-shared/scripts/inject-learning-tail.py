#!/usr/bin/env python3
"""inject-learning-tail.py — install or update the managed learning capture tail block
in every shared SKILL.md.

Iterates over all SKILL.md files under claude-code-shared/skills/*/. Finds the
sentinel-delimited block (<!-- learning-capture:start --> / <!-- learning-capture:end -->)
and replaces it, or appends it if not yet present. Idempotent: a second run makes no
changes when the block is already up to date.

Excludes plugin skill directories (caveman, chrome-devtools) — they live outside the
dotfiles tree and update on their own cadence.

Usage:
  inject-learning-tail.py --check     # show what would change (default)
  inject-learning-tail.py --apply     # write changes
  inject-learning-tail.py --skills-dir <path>   # override skills location
"""

import argparse
import os
import re
import sys

DOTFILES = os.path.expanduser("~/.dotfiles/claude-code-shared")
SKILLS_DIR = os.path.join(DOTFILES, "skills")

PLUGIN_SKILLS = {"caveman", "chrome-devtools"}

SENTINEL_START = "<!-- learning-capture:start -->"
SENTINEL_END = "<!-- learning-capture:end -->"

BLOCK_RE = re.compile(
    r"<!-- learning-capture:start -->.*?<!-- learning-capture:end -->",
    re.S,
)

TAIL_BLOCK = """\
<!-- learning-capture:start -->
## Learning Capture

**Default: do nothing.** Most runs record nothing. Only proceed if an observable
correction-event occurred this run.

If one occurred: identify the `trigger` (tool_failure | backtrack | user_correction |
instruction_gap | redundant_effort | uncategorized), a one-sentence description of what
happened (`brief_evidence`), and `trigger_label` (snake_case if uncategorized, else null).
Spawn the `capture-learning` agent (`subagent_type: capture-learning`) with: `skill`
(this skill's slug), `trigger`, `trigger_label`, `brief_evidence`, `transcript_path`
(absolute path to session transcript). The agent builds the full schema-valid entry,
runs grounding verification, and writes if grounded.
<!-- learning-capture:end -->"""


def inject(text, block):
    """Replace existing block or append. Returns new text (unchanged if already correct)."""
    if SENTINEL_START in text:
        new_text = BLOCK_RE.sub(block, text)
        # Ensure exactly one trailing newline after the block
        if not new_text.endswith("\n"):
            new_text += "\n"
        return new_text
    else:
        # Append: ensure a blank line separator before the block
        stripped = text.rstrip("\n")
        return stripped + "\n\n" + block + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--check", action="store_true", help="dry run (default)")
    g.add_argument("--apply", action="store_true", help="write changes")
    ap.add_argument("--skills-dir", default=SKILLS_DIR)
    args = ap.parse_args()
    apply = args.apply

    skills_dir = args.skills_dir
    if not os.path.isdir(skills_dir):
        sys.exit(f"ERROR: skills-dir not found: {skills_dir}")

    print(f"{'APPLY' if apply else 'CHECK'}  skills-dir={skills_dir}\n")

    changed = ok = missing = skipped = 0

    for entry in sorted(os.scandir(skills_dir), key=lambda e: e.name):
        if not entry.is_dir():
            continue
        skill = entry.name
        if skill in PLUGIN_SKILLS:
            print(f"  SKIP     {skill:40s} (plugin — excluded)")
            skipped += 1
            continue

        path = os.path.join(entry.path, "SKILL.md")
        if not os.path.isfile(path):
            print(f"  MISSING  {skill:40s} (no SKILL.md)")
            missing += 1
            continue

        with open(path, encoding="utf-8") as fh:
            original = fh.read()

        new_text = inject(original, TAIL_BLOCK)

        if new_text == original:
            print(f"  ok       {skill}")
            ok += 1
        else:
            print(f"  CHANGE   {skill}")
            changed += 1
            if apply:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(new_text)

    print(f"\n{'wrote' if apply else 'would change'}: {changed}   already-ok: {ok}   "
          f"missing: {missing}   skipped: {skipped}")
    if not apply and changed:
        print("Run with --apply to write.")


if __name__ == "__main__":
    main()
