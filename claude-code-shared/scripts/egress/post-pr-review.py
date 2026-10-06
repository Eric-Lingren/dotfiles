#!/usr/bin/env python3
"""Post review findings to a GitHub PR as one review with per-line inline comments.

Input: JSON array of {"file", "line", "body"} objects. "body" is the full comment text.

GitHub rejects the entire review if any inline comment targets a line outside the
diff, so each finding is checked against the PR's new-side diff lines first. Findings
with line 0, or on a line outside the diff, are folded into the review summary body.

Usage:
  post-pr-review.py --pr 123 --findings findings.json [--summary "text"] [--repo owner/name] [--dry-run]

Prints the review URL on success. Exits non-zero on gh/API failure.
"""

import argparse
import json
import re
import subprocess
import sys

HUNK_HEADER = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def run_gh(args, stdin=None):
    result = subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"gh {' '.join(args)} failed:\n{result.stderr.strip()}")
    return result.stdout


def commentable_lines(diff_text):
    """Map new-file path -> set of new-side line numbers GitHub accepts comments on."""
    lines_by_file = {}
    current_file = None
    counter = None
    for row in diff_text.splitlines():
        if row.startswith("+++ "):
            path = row[4:]
            current_file = path[2:] if path.startswith("b/") else None
            counter = None
            continue
        if row.startswith("--- ") or row.startswith("diff --git"):
            continue
        header = HUNK_HEADER.match(row)
        if header:
            counter = int(header.group(1))
            continue
        if current_file is None or counter is None:
            continue
        if row.startswith("+") or row.startswith(" "):
            lines_by_file.setdefault(current_file, set()).add(counter)
            counter += 1
        # "-" rows and "\ No newline" markers do not advance the new-side counter.
    return lines_by_file


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pr", required=True, help="PR number")
    parser.add_argument("--findings", required=True, help="Path to findings JSON array")
    parser.add_argument("--summary", default="", help="Review summary body (verdict, counts)")
    parser.add_argument("--repo", help="owner/name; defaults to the current repo")
    parser.add_argument("--dry-run", action="store_true", help="Print the payload, do not post")
    args = parser.parse_args()

    with open(args.findings) as handle:
        findings = json.load(handle)

    repo_flag = ["--repo", args.repo] if args.repo else []
    pr_meta = json.loads(run_gh(["pr", "view", args.pr, *repo_flag, "--json", "headRefOid,url"]))
    repo = args.repo or run_gh(["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]).strip()
    valid_lines = commentable_lines(run_gh(["pr", "diff", args.pr, *repo_flag]))

    inline_comments = []
    folded = []
    for finding in findings:
        path, line, body = finding["file"], int(finding.get("line") or 0), finding["body"]
        if line > 0 and line in valid_lines.get(path, set()):
            inline_comments.append({"path": path, "line": line, "side": "RIGHT", "body": body})
        else:
            location = f"`{path}`" if line == 0 else f"`{path}:L{line}` (outside diff)"
            folded.append(f"- {location}: {body}")

    summary_parts = [args.summary.strip()] if args.summary.strip() else []
    if folded:
        summary_parts.append("**File-level / outside-diff findings**\n\n" + "\n".join(folded))

    payload = {
        "commit_id": pr_meta["headRefOid"],
        "event": "COMMENT",
        "body": "\n\n".join(summary_parts),
        "comments": inline_comments,
    }

    if args.dry_run:
        print(json.dumps(payload, indent=2))
        print(f"inline: {len(inline_comments)}  folded: {len(folded)}", file=sys.stderr)
        return

    response = json.loads(run_gh(
        ["api", "--method", "POST", f"/repos/{repo}/pulls/{args.pr}/reviews", "--input", "-"],
        stdin=json.dumps(payload),
    ))
    print(f"inline: {len(inline_comments)}  folded: {len(folded)}")
    print(response.get("html_url", pr_meta["url"]))


if __name__ == "__main__":
    main()
