#!/usr/bin/env bash
# fetch-github-standup.sh — fetch GitHub PRs authored by the current user.
#
# Outputs JSON to stdout:
#   { "prs": [...], "key_ids": [...] }
#
# Each PR object includes:
#   number, title, body, headRefName, url, state, isDraft,
#   createdAt, updatedAt, mergedAt, reviews, reviewRequests, reviewDecision,
#   reviewers (deduped list of reviewer logins),
#   ciRollup (success|failure|pending|none), unresolvedThreadCount (integer),
#   changedFiles (integer)
#
# Covers open PRs plus PRs merged in the last 21 days. `gh pr list` defaults to
# open only, so merged PRs need their own call or Done is always empty.
# build-standup-data.sh trims merged PRs to the active Linear cycle.
#
# KEY id extraction (e.g. SM-3008, KEY-42) from branch names and PR titles.
#
# Test hooks (env vars — set in tests to avoid real gh calls):
#   GH_PR_LIST_FIXTURE     path to JSON file replacing both `gh pr list` calls
#   GH_PR_MERGED_FIXTURE   optional extra JSON list appended in fixture mode
#   GH_PR_THREADS_FIXTURE  path to JSON file mapping PR numbers to unresolved
#                          thread counts: {"1234": 2, "5678": 0}
#
# Usage: fetch-github-standup.sh
# Exit 0 on success; exit 1 on error.

set -euo pipefail

TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# --- 1. Fetch PR list ---

GH_FIELDS="number,title,body,headRefName,url,state,isDraft,createdAt,updatedAt,mergedAt,reviews,reviewRequests,reviewDecision,statusCheckRollup,changedFiles"

MERGED_LOOKBACK_DAYS=21

if [ -n "${GH_PR_LIST_FIXTURE:-}" ]; then
  cp "$GH_PR_LIST_FIXTURE" "$TMP/open.json"
  if [ -n "${GH_PR_MERGED_FIXTURE:-}" ]; then
    cp "$GH_PR_MERGED_FIXTURE" "$TMP/merged.json"
  else
    echo '[]' > "$TMP/merged.json"
  fi
else
  MERGED_SINCE=$(python3 -c "import datetime as d; print((d.date.today() - d.timedelta(days=$MERGED_LOOKBACK_DAYS)).isoformat())")
  gh pr list --author @me \
    --json "$GH_FIELDS" \
    --limit 100 \
    > "$TMP/open.json"
  gh pr list --author @me --state merged \
    --search "merged:>=$MERGED_SINCE" \
    --json "$GH_FIELDS" \
    --limit 100 \
    > "$TMP/merged.json"
fi

# Concat open + merged, dedupe by PR number.
python3 - "$TMP/open.json" "$TMP/merged.json" > "$TMP/pr_list.json" <<'PYEOF'
import json, sys
seen, out = set(), []
for path in sys.argv[1:]:
    with open(path) as f:
        for pr in json.load(f):
            if pr.get("number") not in seen:
                seen.add(pr.get("number"))
                out.append(pr)
json.dump(out, sys.stdout)
PYEOF

# --- 2. Fetch unresolved review thread counts ---

if [ -n "${GH_PR_THREADS_FIXTURE:-}" ]; then
  cp "$GH_PR_THREADS_FIXTURE" "$TMP/threads.json"
else
  GH_LOGIN=$(gh api user --jq '.login')
  gh api graphql \
    -f query='
      query($login: String!) {
        user(login: $login) {
          pullRequests(first: 100, states: [OPEN, MERGED, CLOSED]) {
            nodes {
              number
              reviewThreads(first: 100) {
                nodes { isResolved }
              }
            }
          }
        }
      }
    ' \
    -f login="$GH_LOGIN" \
    --jq '[.data.user.pullRequests.nodes[] |
            {key: (.number | tostring),
             value: ([.reviewThreads.nodes[] | select(.isResolved == false)] | length)}
          ] | from_entries' \
    > "$TMP/threads.json"
fi

# --- 3. Process into output JSON ---

python3 - "$TMP/pr_list.json" "$TMP/threads.json" <<'PYEOF'
import json, re, sys

pr_list_path = sys.argv[1]
threads_path = sys.argv[2]

with open(pr_list_path) as f:
    pr_list = json.load(f)

with open(threads_path) as f:
    threads_map = json.load(f)

KEY_PATTERN = re.compile(r'\b[A-Z]+-[0-9]+\b')

def compute_ci_rollup(checks):
    if not checks:
        return "none"
    failure_conclusions = {"FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "CANCELLED"}
    pending_statuses = {"QUEUED", "IN_PROGRESS", "WAITING", "PENDING"}
    for c in checks:
        conclusion = (c.get("conclusion") or "").upper()
        if conclusion in failure_conclusions:
            return "failure"
    for c in checks:
        status = (c.get("status") or "").upper()
        if status in pending_statuses:
            return "pending"
    return "success"

key_ids = set()
prs_out = []

for pr in pr_list:
    branch = pr.get("headRefName") or ""
    title = pr.get("title") or ""

    for match in KEY_PATTERN.findall(branch):
        key_ids.add(match)
    for match in KEY_PATTERN.findall(title):
        key_ids.add(match)

    rollup_raw = pr.get("statusCheckRollup") or []
    ci_rollup = compute_ci_rollup(rollup_raw)

    pr_num_str = str(pr.get("number", ""))
    unresolved_count = int(threads_map.get(pr_num_str, 0))

    reviews = []
    for r in (pr.get("reviews") or []):
        author = r.get("author") or {}
        reviews.append({
            "login": author.get("login") or "",
            "state": r.get("state") or ""
        })

    review_requests = []
    for rr in (pr.get("reviewRequests") or []):
        rv = rr.get("requestedReviewer") or rr
        login = rv.get("login") or rv.get("name") or ""
        if login:
            review_requests.append(login)

    # Deduped reviewer logins: review authors + requested reviewers
    reviewer_logins = set(r["login"] for r in reviews if r.get("login"))
    reviewer_logins.update(review_requests)
    reviewers = sorted(reviewer_logins)

    prs_out.append({
        "number": pr.get("number"),
        "title": title,
        "body": pr.get("body") or "",
        "headRefName": branch,
        "url": pr.get("url") or "",
        "state": pr.get("state") or "",
        "isDraft": bool(pr.get("isDraft", False)),
        "createdAt": pr.get("createdAt") or "",
        "updatedAt": pr.get("updatedAt") or "",
        "mergedAt": pr.get("mergedAt"),
        "reviews": reviews,
        "reviewRequests": review_requests,
        "reviewDecision": pr.get("reviewDecision") or None,
        "reviewers": reviewers,
        "ciRollup": ci_rollup,
        "unresolvedThreadCount": unresolved_count,
        "changedFiles": pr.get("changedFiles")
    })

result = {"prs": prs_out, "key_ids": sorted(key_ids)}
print(json.dumps(result, indent=2))
PYEOF
