#!/usr/bin/env bash
# render-standup.sh — render an async standup update from structured data + model prose.
#
# Usage: render-standup.sh <data_json> <prose_json>
#
# Arguments:
#   data_json   Path to JSON output from build-standup-data.sh.
#   prose_json  Path to JSON with model-written prose, one block per section:
#               {
#                 "shipped":   {"lead": "One narrative sentence.", "items": ["Bullet ({KEY-1})", ...]},
#                 "in_flight": {"lead": "...", "items": [...]},
#                 "blockers":  {"lead": "...", "items": ["Fixing CI on {#101} ({KEY-1})", ...]}
#               }
#
# Link tokens: {KEY-123} renders as [KEY-123](<Linear url>), {#123} as [#123](<PR url>).
# Every ticket key or PR number in prose must be a token, so every reference is clickable.
#
# Output: markdown to stdout:
#   **Shipped since last standup** 🚀   ("Shipped this cycle" when nothing is new)
#   **In flight** ⚡
#   **Blockers** 🚧
# Each section: the lead sentence, then one bullet per item.
#
# Exit 0 on success.
# Exit 1 if validation fails (all errors printed to stderr):
#   - unknown or bare (untokenized) ticket/PR reference
#   - em dash anywhere in prose
#   - missing lead, or lead/item over 30 words (tokens not counted)
#   - shipped items missing when something shipped this cycle, or a done_new
#     ticket (or PR when it has no ticket) not referenced in shipped
#   - a blocker PR (any cause) not referenced in blockers
#   - more than 8 shipped, 6 in_flight, or 6 blocker items

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
import re
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)
with open(sys.argv[2]) as f:
    prose = json.load(f)

SECTIONS = [
    # key, max items
    ("shipped", 8),
    ("in_flight", 6),
    ("blockers", 6),
]
MAX_WORDS = 30

TICKET_TOKEN = re.compile(r"\{([A-Z][A-Z0-9]*-\d+)\}")
PR_TOKEN = re.compile(r"\{#(\d+)\}")
BARE_TICKET = re.compile(r"\b[A-Z][A-Z0-9]*-\d+\b")
BARE_PR = re.compile(r"#\d+\b")

# ── Index every ticket and PR in the data ─────────────────────────────────────

tickets, prs = {}, {}

def index_group(g):
    t = g.get("ticket")
    if t and t.get("key"):
        tickets[t["key"]] = t.get("url") or ""
    for p in g.get("prs") or ([g["pr"]] if g.get("pr") else []):
        prs[str(p["number"])] = p.get("url") or ""

for key in ("in_review", "done_new", "done_earlier", "in_progress", "todo"):
    for g in data.get(key) or []:
        index_group(g)
blockers = data.get("blockers") or {}
for entries in blockers.values():
    for e in entries:
        index_group(e)

# ── Validate ──────────────────────────────────────────────────────────────────

errors = []

def strip_tokens(text):
    return PR_TOKEN.sub("", TICKET_TOKEN.sub("", text))

def check_text(where, text):
    if "—" in text:
        errors.append(f"{where}: em dash not allowed: {text!r}")
    for k in TICKET_TOKEN.findall(text):
        if k not in tickets:
            errors.append(f"{where}: unknown ticket {{{k}}}")
    for n in PR_TOKEN.findall(text):
        if n not in prs:
            errors.append(f"{where}: unknown PR {{#{n}}}")
    bare = strip_tokens(text)
    for ref in BARE_TICKET.findall(bare) + BARE_PR.findall(bare):
        errors.append(f"{where}: bare reference {ref!r}, wrap it as {{{ref}}}")
    words = sum(1 for w in bare.split() if any(c.isalnum() for c in w))
    if words > MAX_WORDS:
        errors.append(f"{where}: {words} words (max {MAX_WORDS})")

def refs(section):
    text = " ".join((prose.get(section) or {}).get("items") or [])
    return set(TICKET_TOKEN.findall(text)), set(PR_TOKEN.findall(text))

for section, max_items in SECTIONS:
    block = prose.get(section)
    if not isinstance(block, dict):
        errors.append(f"{section}: missing section object")
        continue
    lead = (block.get("lead") or "").strip()
    items = block.get("items") or []
    if not lead:
        errors.append(f"{section}: lead sentence is required")
    elif "\n" in lead:
        errors.append(f"{section}: lead must be one line")
    else:
        check_text(f"{section}.lead", lead)
    if len(items) > max_items:
        errors.append(f"{section}: {len(items)} items (max {max_items})")
    for i, item in enumerate(items):
        check_text(f"{section}.items[{i}]", item)

done_new = data.get("done_new") or []
done_earlier = data.get("done_earlier") or []

shipped_tickets, shipped_prs = refs("shipped")
if (done_new or done_earlier) and not (prose.get("shipped") or {}).get("items"):
    errors.append("shipped: items are required when anything shipped this cycle")
for g in done_new:
    t = g.get("ticket")
    if t:
        if t["key"] not in shipped_tickets:
            errors.append(f"shipped: done_new ticket {t['key']} is not referenced")
    else:
        for p in g.get("prs") or []:
            if str(p["number"]) not in shipped_prs:
                errors.append(f"shipped: done_new PR #{p['number']} is not referenced")

_, blocker_prs = refs("blockers")
for cause, entries in blockers.items():
    for e in entries:
        n = str(e["pr"]["number"])
        if n not in blocker_prs:
            errors.append(f"blockers: {cause} PR #{n} is not referenced")

if errors:
    for e in sorted(set(errors)):
        print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)

# ── Render ────────────────────────────────────────────────────────────────────

def link(text):
    text = TICKET_TOKEN.sub(lambda m: f"[{m.group(1)}]({tickets[m.group(1)]})" if tickets[m.group(1)] else m.group(1), text)
    return PR_TOKEN.sub(lambda m: f"[#{m.group(1)}]({prs[m.group(1)]})" if prs[m.group(1)] else f"#{m.group(1)}", text)

titles = {
    "shipped": ("Shipped since last standup" if done_new else "Shipped this cycle") + "** 🚀",
    "in_flight": "In flight** ⚡",
    "blockers": "Blockers** 🚧",
}

out = []
for section, _ in SECTIONS:
    block = prose[section]
    out.append(f"**{titles[section]}")
    out.append(link(block["lead"].strip()))
    for item in block.get("items") or []:
        out.append(f"- {link(item.strip())}")
    out.append("")

print("\n".join(out).rstrip())
PYEOF
