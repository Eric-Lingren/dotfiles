#!/usr/bin/env bash
# render-standup.sh — render a standup report from structured data + model prose.
#
# Usage: render-standup.sh <data_json> <prose_json>
#
# Arguments:
#   data_json   Path to JSON output from build-standup-data.sh.
#   prose_json  Path to JSON with model-written prose:
#               {
#                 "summaries": {"SM-3008": "short summary", "101": "PR-only summary"},
#                 "theme": "Theme sentence here.",
#                 "talk_track": ["Line 1.", "Line 2.", "Line 3."]
#               }
#
# Output: markdown report to stdout with sections:
#   ## In Review
#   ## Done
#   ## In Progress
#   ## Blockers
#   ## Theme
#   ## Talk track
#
# Exit 0 on success.
# Exit 1 if talk track validation fails (not 3-4 lines or over 60 words).
#
# State emojis:
#   🔴  red bucket (needs my attention)
#   🟡  yellow bucket (waiting on reviewers)
#   🟢  green bucket (approved)
#   ⚪  white bucket (draft)

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <data_json> <prose_json>" >&2
  exit 1
fi

DATA_JSON="$1"
PROSE_JSON="$2"

if [[ ! -f "$DATA_JSON" ]]; then
  echo "Error: data_json not found: $DATA_JSON" >&2
  exit 1
fi

if [[ ! -f "$PROSE_JSON" ]]; then
  echo "Error: prose_json not found: $PROSE_JSON" >&2
  exit 1
fi

python3 - "$DATA_JSON" "$PROSE_JSON" <<'PYEOF'
import json
import sys
import re

data_path  = sys.argv[1]
prose_path = sys.argv[2]

with open(data_path) as f:
    data = json.load(f)

with open(prose_path) as f:
    prose = json.load(f)

summaries  = prose.get("summaries") or {}
theme      = (prose.get("theme") or "").strip()
talk_track = prose.get("talk_track") or []

# ── Validate talk track ────────────────────────────────────────────────────────

n_lines = len(talk_track)
if n_lines < 3 or n_lines > 4:
    print(f"Error: talk_track must be 3-4 lines (got {n_lines})", file=sys.stderr)
    sys.exit(1)

word_count = sum(len(line.split()) for line in talk_track)
if word_count > 60:
    print(f"Error: talk_track exceeds 60 words (got {word_count})", file=sys.stderr)
    sys.exit(1)

# ── Helpers ───────────────────────────────────────────────────────────────────

BUCKET_EMOJI = {
    "red":    "🔴",
    "yellow": "🟡",
    "green":  "🟢",
    "white":  "⚪",
}

DONE_STATUSES = {"done", "merged", "completed", "closed", "cancelled", "deployed", "released"}

def state_emoji(pr):
    bucket = pr.get("bucket")
    if bucket:
        return BUCKET_EMOJI.get(bucket, "")
    state = (pr.get("state") or "").upper()
    if state == "MERGED":
        return "🟢"
    if pr.get("isDraft"):
        return "⚪"
    return ""

def pr_summary_str(pr, is_done=False):
    num = pr.get("number", "")
    url = pr.get("url") or ""
    title = pr.get("title") or ""
    reviewers = pr.get("reviewers") or []
    age_tag = pr.get("age_tag") or ""
    bucket = pr.get("bucket") or ""

    if url:
        pr_link = f"[#{num}]({url})"
    else:
        pr_link = f"#{num}"

    emoji = state_emoji(pr)

    # summary from prose (keyed by PR number string, or ticket key if available)
    summary = summaries.get(str(num)) or ""

    reviewer_str = ""
    if reviewers:
        reviewer_str = " · " + ", ".join(reviewers)

    age_str = ""
    if not is_done and age_tag and bucket == "yellow":
        age_str = f" ({age_tag})"

    parts = [f"  - {emoji} {pr_link} {title}"]
    if summary:
        parts.append(f" — {summary}")
    if age_str:
        parts.append(age_str)
    if reviewer_str:
        parts.append(reviewer_str)

    return "".join(parts)

def ticket_header(ticket):
    if ticket is None:
        return "(no ticket)"
    key = ticket.get("key") or ""
    url = ticket.get("url") or ""
    title = ticket.get("title") or ""
    project = ticket.get("projectName") or ""

    if url:
        link = f"[{key}]({url})"
    else:
        link = key

    summary = summaries.get(key) or ""
    project_str = f" · *{project}*" if project else ""

    parts = [f"**{link} {title}**"]
    if summary:
        parts.append(f" — {summary}")
    parts.append(project_str)
    return "".join(parts)

def render_group(group, is_done=False):
    lines = []
    ticket = group.get("ticket")
    prs = group.get("prs") or []

    header = ticket_header(ticket)
    lines.append(f"- {header}")

    if not prs:
        lines.append("  - (no PR yet)")
    else:
        for pr in prs:
            lines.append(pr_summary_str(pr, is_done=is_done))

    return lines

# ── Check for violations ───────────────────────────────────────────────────────

violations = data.get("violations") or []
violation_by_ticket = {}
for v in violations:
    tkey = v.get("ticket_key")
    if tkey:
        violation_by_ticket.setdefault(tkey, []).append(v)

# ── Render sections ────────────────────────────────────────────────────────────

output_lines = []

# --- In Review ---
output_lines.append("## In Review\n")
in_review = data.get("in_review") or []
if in_review:
    for group in in_review:
        ticket = group.get("ticket")
        tkey = (ticket or {}).get("key")
        group_lines = render_group(group)
        # Add violation markers
        if tkey and tkey in violation_by_ticket:
            for v in violation_by_ticket[tkey]:
                vtype = v.get("type")
                if vtype == "multiple_prs":
                    prs_str = ", ".join(f"#{n}" for n in v.get("pr_numbers", []))
                    group_lines.append(f"  ⚠️ multiple PRs: {prs_str}")
                elif vtype == "status_disagreement":
                    group_lines.append(f"  ⚠️ status mismatch: {v.get('detail', '')}")
        output_lines.extend(group_lines)
        output_lines.append("")
else:
    output_lines.append("_(none)_\n")

# --- Done ---
output_lines.append("## Done\n")
done_new = data.get("done_new") or []
done_earlier = data.get("done_earlier") or []

if done_new:
    for group in done_new:
        ticket = group.get("ticket")
        tkey = (ticket or {}).get("key")
        prs = group.get("prs") or []

        header = ticket_header(ticket)
        output_lines.append(f"- 🆕 {header}")
        for pr in prs:
            output_lines.append(pr_summary_str(pr, is_done=True))
            if tkey and tkey in violation_by_ticket:
                for v in violation_by_ticket[tkey]:
                    if v.get("type") == "status_disagreement":
                        output_lines.append(f"  ⚠️ {v.get('detail', '')}")
        output_lines.append("")

if done_earlier:
    # Collect all tickets+PRs from done_earlier as a one-liner
    earlier_links = []
    for group in done_earlier:
        ticket = group.get("ticket")
        prs_list = group.get("prs") or []
        if ticket:
            key = ticket.get("key") or ""
            url = ticket.get("url") or ""
            if url:
                earlier_links.append(f"[{key}]({url})")
            else:
                earlier_links.append(key)
        for pr in prs_list:
            num = pr.get("number", "")
            pr_url = pr.get("url") or ""
            if pr_url:
                earlier_links.append(f"[#{num}]({pr_url})")
            else:
                earlier_links.append(f"#{num}")

    if earlier_links:
        output_lines.append(f"- Earlier this cycle: {', '.join(earlier_links)}")
        output_lines.append("")

if not done_new and not done_earlier:
    output_lines.append("_(none)_\n")

# --- In Progress ---
output_lines.append("## In Progress\n")
in_progress = data.get("in_progress") or []
if in_progress:
    for group in in_progress:
        output_lines.extend(render_group(group))
        output_lines.append("")
else:
    output_lines.append("_(none)_\n")

# --- Blockers ---
output_lines.append("## Blockers\n")
blockers = data.get("blockers") or []
if blockers:
    for group in blockers:
        output_lines.extend(render_group(group))
        output_lines.append("")
else:
    output_lines.append("_(none)_\n")

# --- Theme ---
output_lines.append("## Theme\n")
if theme:
    output_lines.append(theme)
    output_lines.append("")
else:
    output_lines.append("_(no theme)_\n")

# --- Talk track ---
output_lines.append("## Talk track\n")
for line in talk_track:
    output_lines.append(f"> {line}")
output_lines.append("")

# ── Emit ──────────────────────────────────────────────────────────────────────

print("\n".join(output_lines))
PYEOF
