#!/usr/bin/env python3
"""Stamp model + effort into skill frontmatter from the central tier map.

Single source of truth: ~/.dotfiles/claude-code-shared/resources/skill-tiers.json
This script reads that map and writes explicit `model:` + `effort:` lines into
each skill's SKILL.md frontmatter. Every skill gets an EXPLICIT model (even T3,
the default) so skills are immune to a later change of the session default.

To re-tier later: edit skill-tiers.json (change what a tier points to, or move a
skill between tiers), then re-run this with --apply. One edit point, all skills
re-stamped.

Frontmatter editing is surgical (no YAML round-trip): it inserts/replaces the
top-level `model:` and `effort:` lines just before the closing `---`, leaving
everything else (folded descriptions, key order) byte-for-byte intact.

Usage:
  sync-skill-tiers.py --check     # show what WOULD change (default if no flag)
  sync-skill-tiers.py --apply     # write the changes
  sync-skill-tiers.py --skills-dir <path>   # override skills location
"""
import argparse
import json
import os
import re
import sys

DOTFILES = os.path.expanduser("~/.dotfiles/claude-code-shared")
CONFIG = os.path.join(DOTFILES, "resources", "skill-tiers.json")
SKILLS_DIR = os.path.join(DOTFILES, "skills")

TOP_KEY = re.compile(r"^(model|effort):", re.I)

DELEGATE_START = "<!-- tier-delegate: managed by sync-skill-tiers.py -->"
DELEGATE_END = "<!-- /tier-delegate -->"
DELEGATE_BLOCK = f"""{DELEGATE_START}
## Delegate menial lookups to Haiku (cost control)

During this skill, push pure read-only lookups DOWN to a cheap subagent instead
of running them on the current model. This covers: multi-file grep/glob,
"where is X defined / what calls Y", mapping a directory, reading many files to
locate something, or fetching a URL for reference.

Use the Agent tool with the `caveman:cavecrew-investigator` subagent (Haiku,
returns a compressed file:line answer). If that subagent is unavailable, spawn a
general agent with `model: haiku`. Keep all reasoning, decisions, and edits on
the current model. Delegate only the menial searching.
{DELEGATE_END}"""

DELEGATE_RE = re.compile(
    re.escape(DELEGATE_START) + r".*?" + re.escape(DELEGATE_END) + r"\n*",
    re.S)


def inject_delegate(post, want):
    """post = closing '---' + body. Insert/remove the managed delegate block
    right after the closing '---'. Idempotent."""
    # strip any existing managed block first
    body = DELEGATE_RE.sub("", post)
    if not want:
        return body
    lines = body.split("\n")
    # lines[0] is the closing '---'
    head, rest = lines[0], "\n".join(lines[1:]).lstrip("\n")
    return head + "\n\n" + DELEGATE_BLOCK + "\n\n" + rest


def load_config(path):
    with open(path) as f:
        cfg = json.load(f)
    tiers = cfg["tiers"]
    for tname, tier in cfg["skills"].items():
        if tier not in tiers:
            sys.exit(f"ERROR: skill '{tname}' -> unknown tier '{tier}'")
    return cfg


def split_frontmatter(text):
    """Return (pre, fm_lines, post) where fm_lines are the lines BETWEEN the
    opening and closing '---'. Returns None if no frontmatter block."""
    if not text.startswith("---\n"):
        return None
    lines = text.split("\n")
    # lines[0] == '---'. Find next '---'.
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            fm = lines[1:i]
            post = "\n".join(lines[i:])  # includes closing --- and body
            return "---\n", fm, post
    return None


def stamp(fm_lines, model, effort):
    """Replace or insert top-level model:/effort: in the frontmatter lines."""
    out = []
    have_model = have_effort = False
    for ln in fm_lines:
        if re.match(r"^model:", ln, re.I):
            out.append(f"model: {model}")
            have_model = True
        elif re.match(r"^effort:", ln, re.I):
            out.append(f"effort: {effort}")
            have_effort = True
        else:
            out.append(ln)
    if not have_model:
        out.append(f"model: {model}")
    if not have_effort:
        out.append(f"effort: {effort}")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--check", action="store_true", help="dry run (default)")
    g.add_argument("--apply", action="store_true", help="write changes")
    ap.add_argument("--config", default=CONFIG)
    ap.add_argument("--skills-dir", default=SKILLS_DIR)
    ap.add_argument("--print-changed", action="store_true",
                    help="also print each changed file path as 'CHANGED<TAB>path' "
                         "(for the git pre-commit hook to re-stage exactly those files)")
    args = ap.parse_args()
    apply = args.apply

    cfg = load_config(args.config)
    tiers = cfg["tiers"]
    delegate = set(cfg.get("delegate", []))
    changed = missing = ok = 0
    changed_paths = []

    print(f"{'APPLY' if apply else 'CHECK'}  config={args.config}\n")
    for skill, tier in cfg["skills"].items():
        model = tiers[tier]["model"]
        effort = tiers[tier]["effort"]
        path = os.path.join(args.skills_dir, skill, "SKILL.md")
        if not os.path.isfile(path):
            print(f"  MISSING  {skill:32s} (no {path})")
            missing += 1
            continue
        with open(path) as f:
            text = f.read()
        parts = split_frontmatter(text)
        if parts is None:
            print(f"  NO-FM    {skill:32s} (no frontmatter block, skipped)")
            missing += 1
            continue
        pre, fm, post = parts
        new_fm = stamp(list(fm), model, effort)
        new_post = inject_delegate(post, skill in delegate)
        new_text = pre + "\n".join(new_fm) + "\n" + new_post
        deleg_tag = " +delegate" if skill in delegate else ""
        if new_text == text:
            print(f"  ok       {skill:32s} {tier} -> {model}/{effort}{deleg_tag}")
            ok += 1
            continue
        changed += 1
        changed_paths.append(path)
        print(f"  CHANGE   {skill:32s} {tier} -> {model}/{effort}{deleg_tag}")
        if apply:
            with open(path, "w") as f:
                f.write(new_text)

    print(f"\n{'wrote' if apply else 'would change'}: {changed}   already-ok: {ok}   missing: {missing}")
    if not apply and changed:
        print("Run with --apply to write.")
    if args.print_changed:
        for p in changed_paths:
            print(f"CHANGED\t{p}")


if __name__ == "__main__":
    main()
