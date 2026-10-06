#!/usr/bin/env bash
# build-standup-data.sh — build structured standup JSON from Linear + GitHub data
#
# Usage:
#   build-standup-data.sh <linear_json> <github_json> [--standups-dir <path>]
#
# Args:
#   linear_json      Path to JSON array output from fetch-linear-standup.sh
#                    Each item: {id, key, title, status, statusType, completedAt,
#                                cycleStartsAt, url, parentKey, epicKey, projectName}
#   github_json      Path to JSON object output from fetch-github-standup.sh
#                    Shape: {prs: [...], key_ids: [...]}
#
# Options:
#   --standups-dir   Directory containing prior standups as YYYY-MM-DD.md files.
#                    The newest filename date before today is used as the cutoff.
#                    If missing or empty: all merged PRs go to done_new,
#                    since_last_standup_cutoff is null.
#
# Env:
#   STANDUP_NOW      ISO 8601 datetime string for "now" (for deterministic tests).
#                    Defaults to current UTC time.
#
# Output (stdout): one structured JSON object:
#   {
#     "in_review":   [{ticket, prs: [{...bucket, age_tag}]}],
#     "done_new":    [{ticket, prs}],
#     "done_earlier":[{ticket, prs}],
#     "in_progress": [{ticket, prs}],
#     "todo":        [{ticket, prs: []}],
#     "blockers":    [{ticket, prs}],
#     "theme_signals":{distinct_reviewers, small_prs, ci_green_ratio, delivery_count,
#                      shipped_cycle_count},
#     "violations":  [{type, ...}],
#     "since_last_standup_cutoff": "YYYY-MM-DD" | null
#   }
#
# Bucket rules (for OPEN non-draft PRs in in_review):
#   red    — ciRollup=="failure" OR any reviewer's latest state=="CHANGES_REQUESTED"
#            OR unresolvedThreadCount > 0
#   green  — all reviewers have APPROVED (latest), at least one review, no issues
#   yellow — everything else (no reviews yet, or review requested but no issues)
#   white  — isDraft==true (listed under in_progress)
#
# Tickets with no open/merged PR route by Linear statusType:
#   completed            → done_new / done_earlier (by completedAt vs cutoff)
#   triage|backlog|unstarted → todo
#   canceled|duplicate   → dropped
#   started or unknown   → in_progress
#
# Merged PRs before the active cycle start (any ticket's cycleStartsAt) are dropped.
#
# Violations:
#   multiple_prs       — a Linear ticket has more than one PR
#   status_disagreement — PR merged but ticket not in a done-type status,
#                         OR ticket done but PR still open/not-merged
#
# Exit 0 on success, exit 1 on error.

set -euo pipefail

# ─── Argument parsing ─────────────────────────────────────────────────────────

STANDUPS_DIR=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --standups-dir)
      STANDUPS_DIR="$2"
      shift 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
  echo "Usage: $0 <linear_json> <github_json> [--standups-dir <path>]" >&2
  exit 1
fi

LINEAR_JSON="${POSITIONAL[0]}"
GITHUB_JSON="${POSITIONAL[1]}"

if [[ ! -f "$LINEAR_JSON" ]]; then
  echo "Error: linear_json not found: $LINEAR_JSON" >&2
  exit 1
fi

if [[ ! -f "$GITHUB_JSON" ]]; then
  echo "Error: github_json not found: $GITHUB_JSON" >&2
  exit 1
fi

# ─── Main processing (Python) ─────────────────────────────────────────────────

python3 - "$LINEAR_JSON" "$GITHUB_JSON" "$STANDUPS_DIR" "${STANDUP_NOW:-}" <<'PYEOF'
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

linear_path  = sys.argv[1]
github_path  = sys.argv[2]
standups_dir = sys.argv[3]  # may be empty string
now_str      = sys.argv[4]  # may be empty string

# ── "Now" ────────────────────────────────────────────────────────────────────

def parse_iso(s):
    """Parse ISO 8601 string to UTC-aware datetime, or None."""
    if not s:
        return None
    s = s.rstrip("Z")
    if "+" in s:
        s = s[:s.index("+")]
    try:
        return datetime.fromisoformat(s).replace(tzinfo=timezone.utc)
    except ValueError:
        return None

if now_str:
    NOW = parse_iso(now_str)
    if NOW is None:
        print(f"Error: STANDUP_NOW is not a valid ISO 8601 string: {now_str!r}", file=sys.stderr)
        sys.exit(1)
else:
    NOW = datetime.now(tz=timezone.utc)

# ── Load inputs ───────────────────────────────────────────────────────────────

with open(linear_path) as f:
    linear_tickets = json.load(f)

with open(github_path) as f:
    gh_data = json.load(f)

prs = gh_data.get("prs", [])

# ── Cutoff from standups_dir ─────────────────────────────────────────────────

DATE_RE = re.compile(r'^(\d{4}-\d{2}-\d{2})\.md$')
cutoff_date_str = None

if standups_dir:
    sd = Path(standups_dir)
    if sd.is_dir():
        dates = []
        for f in sd.iterdir():
            m = DATE_RE.match(f.name)
            # Skip today's file so a same-day rerun still compares to the prior standup
            if m and m.group(1) < NOW.date().isoformat():
                dates.append(m.group(1))
        if dates:
            cutoff_date_str = max(dates)

# ── Active cycle start (trims merged PRs from earlier cycles) ────────────────

cycle_start = None
for t in linear_tickets:
    cs = parse_iso(t.get("cycleStartsAt") or "")
    if cs:
        cycle_start = cs
        break

def merged_in_cycle(pr):
    if cycle_start is None:
        return True
    merged_at = parse_iso(pr.get("mergedAt") or "")
    return merged_at is None or merged_at >= cycle_start

def is_new_since_cutoff(ts_str):
    if not cutoff_date_str:
        return True
    ts = parse_iso(ts_str or "")
    if ts is None:
        return True
    return ts.date() > datetime.fromisoformat(cutoff_date_str).date()

# ── KEY extraction from PR branch + title ─────────────────────────────────────

KEY_PAT = re.compile(r'\b[A-Z]+-[0-9]+\b')

def extract_keys(pr):
    keys = set()
    for text in (pr.get("headRefName") or "", pr.get("title") or ""):
        keys.update(KEY_PAT.findall(text))
    return keys

# ── Bucket classification ─────────────────────────────────────────────────────

DONE_STATUSES = {"done", "merged", "completed", "closed", "cancelled", "deployed", "released"}

def is_done_status(status_str):
    return (status_str or "").lower().strip() in DONE_STATUSES

def latest_review_states(reviews):
    """Return dict of {reviewer_login: latest_state} (last entry wins per reviewer)."""
    latest = {}
    for r in (reviews or []):
        login = r.get("login") or ""
        state = r.get("state") or ""
        if login:
            latest[login] = state
    return latest

def classify_bucket(pr):
    """Return bucket string: red, yellow, green, or white."""
    if pr.get("isDraft"):
        return "white"

    state = (pr.get("state") or "").upper()
    # Only classify open PRs; merged/closed handled elsewhere
    if state != "OPEN":
        return None

    ci = pr.get("ciRollup") or "none"
    unresolved = int(pr.get("unresolvedThreadCount") or 0)
    reviews = latest_review_states(pr.get("reviews") or [])

    has_changes_requested = any(s == "CHANGES_REQUESTED" for s in reviews.values())
    has_ci_failure = ci == "failure"
    has_unresolved = unresolved > 0

    if has_ci_failure or has_changes_requested or has_unresolved:
        return "red"

    all_approved = bool(reviews) and all(s == "APPROVED" for s in reviews.values())
    if all_approved:
        return "green"

    return "yellow"

# ── Age tag ───────────────────────────────────────────────────────────────────

def age_tag(pr):
    """Return 'waiting Nd' based on updatedAt (last activity)."""
    ts = parse_iso(pr.get("updatedAt") or "") or parse_iso(pr.get("createdAt") or "")
    if ts is None:
        return "waiting ?d"
    days = max(0, (NOW - ts).days)
    return f"waiting {days}d"

# ── Build ticket index ────────────────────────────────────────────────────────

ticket_by_key = {t["key"]: t for t in linear_tickets}

# ── Pair PRs to tickets ───────────────────────────────────────────────────────

# pr_keys[pr_number] = set of matched ticket keys
pr_to_tickets = {}   # pr_number -> [ticket_key, ...]
ticket_to_prs = {}   # ticket_key -> [pr_number, ...]

for pr in prs:
    num = pr["number"]
    found_keys = []
    for k in extract_keys(pr):
        if k in ticket_by_key:
            found_keys.append(k)
    pr_to_tickets[num] = found_keys
    for k in found_keys:
        ticket_to_prs.setdefault(k, []).append(num)

pr_by_number = {pr["number"]: pr for pr in prs}

# ── Violations ────────────────────────────────────────────────────────────────

violations = []

# multiple_prs
for tkey, pr_nums in ticket_to_prs.items():
    # Count only non-closed PRs
    non_closed = [n for n in pr_nums if (pr_by_number[n].get("state") or "").upper() != "CLOSED"]
    if len(non_closed) > 1:
        violations.append({
            "type": "multiple_prs",
            "ticket_key": tkey,
            "pr_numbers": sorted(non_closed)
        })

# status_disagreement
for pr in prs:
    state = (pr.get("state") or "").upper()
    if state == "CLOSED":
        continue
    for tkey in pr_to_tickets.get(pr["number"], []):
        ticket = ticket_by_key[tkey]
        ticket_done = is_done_status(ticket.get("status") or "")
        pr_merged = state == "MERGED"
        if pr_merged and not ticket_done:
            violations.append({
                "type": "status_disagreement",
                "ticket_key": tkey,
                "ticket_status": ticket.get("status"),
                "pr_number": pr["number"],
                "pr_state": state,
                "detail": "PR merged but ticket not in done-type status"
            })
        elif ticket_done and not pr_merged and state == "OPEN":
            violations.append({
                "type": "status_disagreement",
                "ticket_key": tkey,
                "ticket_status": ticket.get("status"),
                "pr_number": pr["number"],
                "pr_state": state,
                "detail": "Ticket done but PR still open"
            })

# ── Build output groups ───────────────────────────────────────────────────────

def pr_summary(pr, bucket=None):
    out = {
        "number": pr["number"],
        "title": pr.get("title") or "",
        "headRefName": pr.get("headRefName") or "",
        "url": pr.get("url") or "",
        "state": pr.get("state") or "",
        "ciRollup": pr.get("ciRollup"),
        "unresolvedThreadCount": pr.get("unresolvedThreadCount"),
        "changedFiles": pr.get("changedFiles"),
        "createdAt": pr.get("createdAt"),
        "updatedAt": pr.get("updatedAt"),
        "mergedAt": pr.get("mergedAt"),
        "age_tag": age_tag(pr),
        "reviewers": pr.get("reviewers") or [],
    }
    if bucket:
        out["bucket"] = bucket
    return out

def ticket_summary(tkey):
    if tkey is None:
        return None
    t = ticket_by_key.get(tkey)
    if t is None:
        return None
    return {
        "key": t["key"],
        "title": t["title"],
        "status": t["status"],
        "statusType": t.get("statusType"),
        "completedAt": t.get("completedAt"),
        "url": t["url"],
        "parentKey": t.get("parentKey"),
        "epicKey": t.get("epicKey"),
        "projectName": t.get("projectName") or None,
    }

# Group: buckets for open non-draft PRs
in_review_items  = []  # {ticket_key_or_none, pr}
in_progress_items = [] # {ticket_key_or_none, pr} — draft PRs + unmatched open tickets
done_new_items    = []
done_earlier_items = []

seen_pr_numbers = set()
placed_ticket_keys = set()

for pr in prs:
    num = pr["number"]
    seen_pr_numbers.add(num)
    state = (pr.get("state") or "").upper()

    if state == "CLOSED":
        continue  # closed (not merged) PRs not shown

    bucket = classify_bucket(pr)
    tkeys = pr_to_tickets.get(num, [])
    tkey = tkeys[0] if tkeys else None  # primary ticket (first match)

    if state == "MERGED":
        if not merged_in_cycle(pr):
            continue
        if is_new_since_cutoff(pr.get("mergedAt")):
            done_new_items.append((tkey, pr))
        else:
            done_earlier_items.append((tkey, pr))
    elif bucket == "white":
        in_progress_items.append((tkey, pr))
    elif bucket in ("red", "yellow", "green"):
        in_review_items.append((tkey, pr))
    else:
        continue
    placed_ticket_keys.update(tkeys)

# Tickets with no placed PR route by Linear status type
TODO_TYPES = {"triage", "backlog", "unstarted"}
todo_items = []

for t in linear_tickets:
    if t["key"] in placed_ticket_keys:
        continue
    stype = (t.get("statusType") or "").lower()
    if stype in ("canceled", "duplicate"):
        continue
    if stype == "completed":
        if is_new_since_cutoff(t.get("completedAt")):
            done_new_items.append((t["key"], None))
        else:
            done_earlier_items.append((t["key"], None))
    elif stype in TODO_TYPES:
        todo_items.append((t["key"], None))
    else:
        in_progress_items.append((t["key"], None))

# ── Build grouped output ─────────────────────────────────────────────────────

def group_by_ticket(items):
    """items: list of (ticket_key_or_none, pr_or_none)"""
    from collections import defaultdict
    groups = {}      # ticket_key_or_None -> list of prs
    order = []
    for tkey, pr in items:
        k = tkey if tkey else "__no_ticket__"
        if k not in groups:
            groups[k] = []
            order.append(k)
        if pr is not None:
            groups[k].append(pr)
    result = []
    for k in order:
        real_key = None if k == "__no_ticket__" else k
        result.append({
            "ticket": ticket_summary(real_key),
            "prs": groups[k]
        })
    return result

def group_in_review(items):
    from collections import defaultdict
    groups = {}
    order = []
    for tkey, pr in items:
        k = tkey if tkey else "__no_ticket__"
        if k not in groups:
            groups[k] = []
            order.append(k)
        bucket = classify_bucket(pr)
        groups[k].append(pr_summary(pr, bucket=bucket))
    result = []
    for k in order:
        real_key = None if k == "__no_ticket__" else k
        result.append({
            "ticket": ticket_summary(real_key),
            "prs": groups[k]
        })
    return result

def group_done(items):
    from collections import defaultdict
    groups = {}
    order = []
    for tkey, pr in items:
        k = tkey if tkey else "__no_ticket__"
        if k not in groups:
            groups[k] = []
            order.append(k)
        if pr is not None:
            groups[k].append(pr_summary(pr))
    result = []
    for k in order:
        real_key = None if k == "__no_ticket__" else k
        result.append({
            "ticket": ticket_summary(real_key),
            "prs": groups[k]
        })
    return result

def group_in_progress(items):
    """Items can have pr=None (ticket only) or pr=draft."""
    from collections import defaultdict
    groups = {}
    order = []
    for tkey, pr in items:
        k = tkey if tkey else "__no_ticket__"
        if k not in groups:
            groups[k] = []
            order.append(k)
        if pr is not None:
            groups[k].append(pr_summary(pr, bucket="white"))
    result = []
    for k in order:
        real_key = None if k == "__no_ticket__" else k
        result.append({
            "ticket": ticket_summary(real_key),
            "prs": groups[k]
        })
    return result

in_review_out   = group_in_review(in_review_items)
done_new_out    = group_done(done_new_items)
done_earlier_out = group_done(done_earlier_items)
in_progress_out = group_in_progress(in_progress_items)
todo_out        = group_by_ticket(todo_items)

# ── Blockers: red-bucket in_review items ──────────────────────────────────────

blockers_out = []
for group in in_review_out:
    red_prs = [p for p in group["prs"] if p.get("bucket") == "red"]
    if red_prs:
        blockers_out.append({"ticket": group["ticket"], "prs": red_prs})

# ── Theme signals ─────────────────────────────────────────────────────────────

all_open_non_draft = [pr for pr in prs
                      if (pr.get("state") or "").upper() == "OPEN"
                      and not pr.get("isDraft")]

# distinct_reviewers: unique reviewers across all open non-draft PRs
reviewer_logins = set()
for pr in all_open_non_draft:
    for r in (pr.get("reviews") or []):
        login = r.get("login") or ""
        if login:
            reviewer_logins.add(login)
distinct_reviewers = len(reviewer_logins)

# small_prs: count of open non-draft PRs with changedFiles <= 10
# If changedFiles is absent everywhere, set to null
changed_files_values = [pr.get("changedFiles") for pr in all_open_non_draft]
has_changed_files = any(v is not None for v in changed_files_values)
if has_changed_files:
    small_prs = sum(1 for v in changed_files_values if v is not None and v <= 10)
else:
    small_prs = None

# ci_green_ratio: fraction of open non-draft PRs with ciRollup == "success"
if all_open_non_draft:
    ci_green_count = sum(1 for pr in all_open_non_draft
                         if pr.get("ciRollup") == "success")
    ci_green_ratio = round(ci_green_count / len(all_open_non_draft), 3)
else:
    ci_green_ratio = None

# delivery_count: shipped items since last standup (PRs, or the ticket when it has none)
def shipped_count(groups):
    return sum(len(g["prs"]) or 1 for g in groups)

delivery_count = shipped_count(done_new_out)
shipped_cycle_count = delivery_count + shipped_count(done_earlier_out)

theme_signals = {
    "distinct_reviewers": distinct_reviewers,
    "small_prs": small_prs,
    "ci_green_ratio": ci_green_ratio,
    "delivery_count": delivery_count,
    "shipped_cycle_count": shipped_cycle_count,
}

# ── Final output ──────────────────────────────────────────────────────────────

result = {
    "in_review":   in_review_out,
    "done_new":    done_new_out,
    "done_earlier": done_earlier_out,
    "in_progress": in_progress_out,
    "todo":        todo_out,
    "blockers":    blockers_out,
    "theme_signals": theme_signals,
    "violations":  violations,
    "since_last_standup_cutoff": cutoff_date_str,
}

print(json.dumps(result, indent=2))
PYEOF
