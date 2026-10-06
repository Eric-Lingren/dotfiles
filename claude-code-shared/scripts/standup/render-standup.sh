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
#                 "shipped_track": ["What shipped.", "What it unlocks."],
#                 "talk_track": ["What is waiting.", "What is next."]
#               }
#
# Output: markdown report to stdout with sections:
#   ## 🟣 Done
#   ## 🟢 In Review
#   ## 🟡 In Progress
#   ## ⚪ Todo
#   ## Blockers
#   ## Theme
#   ## Talk track   (shipped_track lines first, then talk_track)
#
# Exit 0 on success.
# Exit 1 if talk track validation fails:
#   shipped_track 1-3 lines (required when anything shipped this cycle, else 0-3),
#   talk_track 2-3 lines, 80 words max across both.
#
# Status circles match Linear's workflow colors, keyed off the ticket's statusType:
#   ⚪  todo / backlog   🟡  in progress   🟢  in review   🟣  done / shipped
#
# PR review markers (open PRs only, kept off the circles so colors mean one thing):
#   🚩  needs my attention (CI failing, changes requested, unresolved threads)
#   ⏳  waiting on reviewers
#   ✅  approved
#   📝  draft

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

data_path  = sys.argv[1]
prose_path = sys.argv[2]

with open(data_path) as f:
    data = json.load(f)

with open(prose_path) as f:
    prose = json.load(f)

summaries     = prose.get("summaries") or {}
theme         = (prose.get("theme") or "").strip()
shipped_track = prose.get("shipped_track") or []
talk_track    = prose.get("talk_track") or []

done_new     = data.get("done_new") or []
done_earlier = data.get("done_earlier") or []

def shipped_count(groups):
    return sum(len(g.get("prs") or []) or 1 for g in groups)

signals = data.get("theme_signals") or {}
shipped_new   = shipped_count(done_new)
shipped_cycle = signals.get("shipped_cycle_count")
if shipped_cycle is None:
    shipped_cycle = shipped_new + shipped_count(done_earlier)

# ── Validate talk track ────────────────────────────────────────────────────────

def fail(msg):
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(1)

if shipped_cycle > 0 and not shipped_track:
    fail(f"shipped_track is required when {shipped_cycle} item(s) shipped this cycle")
if len(shipped_track) > 3:
    fail(f"shipped_track must be at most 3 lines (got {len(shipped_track)})")
if len(talk_track) < 2 or len(talk_track) > 3:
    fail(f"talk_track must be 2-3 lines (got {len(talk_track)})")

word_count = sum(len(line.split()) for line in shipped_track + talk_track)
if word_count > 80:
    fail(f"talk track exceeds 80 words (got {word_count})")

# ── Helpers ───────────────────────────────────────────────────────────────────

CIRCLE = {"todo": "⚪", "progress": "🟡", "review": "🟢", "done": "🟣"}

REVIEW_MARKER = {
    "red":    "🚩",
    "yellow": "⏳",
    "green":  "✅",
    "white":  "📝",
}

TODO_TYPES = {"triage", "backlog", "unstarted"}

def ticket_circle(ticket, fallback):
    """Linear status color for a ticket; fallback is the section's phase."""
    if ticket is None:
        return CIRCLE[fallback]
    stype = (ticket.get("statusType") or "").lower()
    name = (ticket.get("status") or "").lower()
    if stype == "completed":
        return CIRCLE["done"]
    if stype in TODO_TYPES:
        return CIRCLE["todo"]
    if stype == "started":
        return CIRCLE["review"] if "review" in name else CIRCLE["progress"]
    return CIRCLE[fallback]

def pr_marker(pr):
    state = (pr.get("state") or "").upper()
    if state == "MERGED":
        return CIRCLE["done"]
    bucket = pr.get("bucket")
    if bucket:
        return REVIEW_MARKER.get(bucket, "")
    if pr.get("isDraft"):
        return REVIEW_MARKER["white"]
    return ""

def pr_link(pr):
    num = pr.get("number", "")
    url = pr.get("url") or ""
    return f"[#{num}]({url})" if url else f"#{num}"

def pr_summary_str(pr, is_done=False):
    num = pr.get("number", "")
    title = pr.get("title") or ""
    reviewers = pr.get("reviewers") or []
    age_tag = pr.get("age_tag") or ""
    bucket = pr.get("bucket") or ""

    summary = summaries.get(str(num)) or ""

    parts = [f"  - {pr_marker(pr)} {pr_link(pr)} {title}"]
    if summary:
        parts.append(f" — {summary}")
    if not is_done and age_tag and bucket == "yellow":
        parts.append(f" ({age_tag})")
    if reviewers:
        parts.append(" · " + ", ".join(reviewers))
    return "".join(parts)

def ticket_header(ticket):
    if ticket is None:
        return "(no ticket)"
    key = ticket.get("key") or ""
    url = ticket.get("url") or ""
    title = ticket.get("title") or ""
    project = ticket.get("projectName") or ""

    link = f"[{key}]({url})" if url else key
    summary = summaries.get(key) or ""

    parts = [f"**{link} {title}**"]
    if summary:
        parts.append(f" — {summary}")
    if project:
        parts.append(f" · *{project}*")
    return "".join(parts)

def render_group(group, phase, prefix="", is_done=False, no_pr_note="(no PR yet)"):
    ticket = group.get("ticket")
    prs = group.get("prs") or []
    lines = [f"- {ticket_circle(ticket, phase)} {prefix}{ticket_header(ticket)}"]
    if prs:
        for pr in prs:
            lines.append(pr_summary_str(pr, is_done=is_done))
    elif no_pr_note:
        lines.append(f"  - {no_pr_note}")
    return lines

# ── Check for violations ───────────────────────────────────────────────────────

violations = data.get("violations") or []
violation_by_ticket = {}
for v in violations:
    tkey = v.get("ticket_key")
    if tkey:
        violation_by_ticket.setdefault(tkey, []).append(v)

def violation_lines(ticket, types):
    tkey = (ticket or {}).get("key")
    out = []
    for v in violation_by_ticket.get(tkey, []):
        vtype = v.get("type")
        if vtype not in types:
            continue
        if vtype == "multiple_prs":
            prs_str = ", ".join(f"#{n}" for n in v.get("pr_numbers", []))
            out.append(f"  ⚠️ multiple PRs: {prs_str}")
        elif vtype == "status_disagreement":
            out.append(f"  ⚠️ status mismatch: {v.get('detail', '')}")
    return out

# ── Render sections ────────────────────────────────────────────────────────────

output_lines = []

def section(title, groups, phase, empty="_(none)_", compact=False, **kw):
    output_lines.append(f"## {title}\n")
    if not groups:
        output_lines.append(f"{empty}\n")
        return
    for group in groups:
        output_lines.extend(render_group(group, phase, **kw))
        output_lines.extend(violation_lines(group.get("ticket"), {"multiple_prs", "status_disagreement"}))
        if not compact:
            output_lines.append("")
    if compact:
        output_lines.append("")

# --- Done (first: shipped work leads the report) ---
output_lines.append(f"## {CIRCLE['done']} Done\n")
if shipped_cycle:
    output_lines.append(f"**Shipped this cycle: {shipped_cycle}** · {shipped_new} since last standup\n")
if done_new:
    output_lines.append("### 🆕 Since last standup\n")
    for group in done_new:
        output_lines.extend(render_group(group, "done", prefix="🆕 ", is_done=True, no_pr_note=None))
        output_lines.extend(violation_lines(group.get("ticket"), {"status_disagreement"}))
        output_lines.append("")
if done_earlier:
    output_lines.append("### Earlier this cycle\n")
    for group in done_earlier:
        output_lines.extend(render_group(group, "done", is_done=True, no_pr_note=None))
        output_lines.append("")
if not done_new and not done_earlier:
    output_lines.append("_(none)_\n")

section(f"{CIRCLE['review']} In Review", data.get("in_review") or [], "review")
section(f"{CIRCLE['progress']} In Progress", data.get("in_progress") or [], "progress")
section(f"{CIRCLE['todo']} Todo", data.get("todo") or [], "todo", compact=True, no_pr_note=None)

# --- Blockers ---
output_lines.append("## Blockers\n")
blockers = data.get("blockers") or []
if blockers:
    for group in blockers:
        output_lines.extend(render_group(group, "review"))
        output_lines.append("")
else:
    output_lines.append("_(none)_\n")

# --- Theme ---
output_lines.append("## Theme\n")
output_lines.append(theme if theme else "_(no theme)_")
output_lines.append("")

# --- Talk track ---
output_lines.append("## Talk track\n")
for line in shipped_track + talk_track:
    output_lines.append(f"> {line}")
output_lines.append("")

# ── Emit ──────────────────────────────────────────────────────────────────────

print("\n".join(output_lines))
PYEOF
