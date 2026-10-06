#!/usr/bin/env bash
# Tests for build-standup-data.sh
# Uses fixture JSON files — no real API calls are made.
#
# Usage: bash test-build-standup-data.sh
# Exit 0 = all tests passed. Exit 1 = one or more failed.

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPTS_DIR/standup/build-standup-data.sh"
FIXTURES="$(dirname "$0")/fixtures/build-standup-data"

LINEAR_FIXTURE="$FIXTURES/linear.json"
GITHUB_FIXTURE="$FIXTURES/github.json"
STANDUPS_FIXTURE="$FIXTURES/standups"

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# STANDUP_NOW set to a fixed UTC time so age tags are deterministic
# updatedAt "2026-09-20T10:00:00Z" → 10 days before 2026-10-01
export STANDUP_NOW="2026-10-01T00:00:00Z"

# --- harness helpers ---

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local actual="$1" expected="$2" desc="$3"
  if [ "$actual" = "$expected" ]; then
    assert_pass "$desc"
  else
    assert_fail "$desc (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local text="$1" pattern="$2" desc="$3"
  if echo "$text" | grep -q "$pattern"; then
    assert_pass "$desc"
  else
    assert_fail "$desc (pattern '$pattern' not found)"
    echo "    Output (first 400 chars): ${text:0:400}"
  fi
}

assert_not_contains() {
  local text="$1" pattern="$2" desc="$3"
  if echo "$text" | grep -q "$pattern"; then
    assert_fail "$desc (pattern '$pattern' unexpectedly found)"
    echo "    Output (first 400 chars): ${text:0:400}"
  else
    assert_pass "$desc"
  fi
}

assert_json_valid() {
  local text="$1" desc="$2"
  if echo "$text" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    assert_pass "$desc"
  else
    assert_fail "$desc (output is not valid JSON)"
    echo "    Output (first 400 chars): ${text:0:400}"
  fi
}

assert_exit_zero() {
  local code="$1" desc="$2"
  if [ "$code" -eq 0 ]; then
    assert_pass "$desc"
  else
    assert_fail "$desc (exited $code, expected 0)"
  fi
}

jval() {
  # Extract a Python expression from JSON on stdin
  local expr="$1"
  python3 -c "import json,sys; d=json.load(sys.stdin); print($expr)"
}

# ── Run main fixture once ──────────────────────────────────────────────────────

set +e
OUT=$(bash "$SCRIPT" "$LINEAR_FIXTURE" "$GITHUB_FIXTURE" \
      --standups-dir "$STANDUPS_FIXTURE" 2>"$TMP/main.err")
EXIT_MAIN=$?
set -e

# --- Test 1: script exists and is executable ---
echo "=== T1: script exists ==="
if [ -f "$SCRIPT" ]; then
  assert_pass "build-standup-data.sh exists"
else
  assert_fail "build-standup-data.sh not found at $SCRIPT"
fi
if [ -x "$SCRIPT" ]; then
  assert_pass "script is executable"
else
  assert_fail "script is not executable"
fi

# --- Test 2: exit 0 and valid JSON ---
echo ""
echo "=== T2: exit 0 and valid JSON ==="
assert_exit_zero "$EXIT_MAIN" "exits 0 with fixture inputs"
assert_json_valid "$OUT" "output is valid JSON"

# --- Test 3: output shape ---
echo ""
echo "=== T3: output shape ==="
KEYS=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
expected = {'in_review','done_new','done_earlier','in_progress','todo','blockers','theme_signals','violations','since_last_standup_cutoff'}
actual = set(d.keys())
missing = expected - actual
extra = actual - expected
if missing: print('MISSING: ' + ', '.join(sorted(missing)))
elif extra: print('EXTRA: ' + ', '.join(sorted(extra)))
else: print('OK')
")
assert_eq "$KEYS" "OK" "all required top-level keys present"

# --- Test 4: bucket red — CHANGES_REQUESTED ---
echo ""
echo "=== T4: bucket red — CHANGES_REQUESTED ==="
BUCKET_101=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 101:
            print(pr['bucket'])
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$BUCKET_101" "red" "PR 101 (CHANGES_REQUESTED) classified as red"

# --- Test 5: bucket red — CI failure ---
echo ""
echo "=== T5: bucket red — CI failure ==="
BUCKET_102=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 102:
            print(pr['bucket'])
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$BUCKET_102" "red" "PR 102 (CI failure) classified as red"

# --- Test 6: bucket red — unresolved threads ---
echo ""
echo "=== T6: bucket red — unresolved threads ==="
BUCKET_110=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 110:
            print(pr['bucket'])
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$BUCKET_110" "red" "PR 110 (unresolvedThreadCount=2) classified as red"

# --- Test 7: bucket yellow — no reviews ---
echo ""
echo "=== T7: bucket yellow — no reviews ==="
BUCKET_106=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 106:
            print(pr['bucket'])
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$BUCKET_106" "yellow" "PR 106 (no reviews) classified as yellow"

# --- Test 8: bucket green — approved, no issues ---
echo ""
echo "=== T8: bucket green — approved ==="
BUCKET_108=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 108:
            print(pr['bucket'])
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$BUCKET_108" "green" "PR 108 (APPROVED, CI success) classified as green"

# --- Test 9: bucket white — draft ---
echo ""
echo "=== T9: bucket white — draft ==="
# Draft PR 104 should be in in_progress, not in_review
IN_REVIEW_HAS_104=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 104:
            print('FOUND')
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$IN_REVIEW_HAS_104" "NOT_FOUND" "draft PR 104 not in in_review"

IN_PROGRESS_HAS_104=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_progress']:
    for pr in group['prs']:
        if pr['number'] == 104:
            print(pr.get('bucket', 'NO_BUCKET'))
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$IN_PROGRESS_HAS_104" "white" "draft PR 104 in in_progress with bucket=white"

# --- Test 10: age tag computation ---
echo ""
echo "=== T10: age tag computation ==="
# PR 101 updatedAt = 2026-09-20T10:00:00Z, NOW = 2026-10-01T00:00:00Z → 10 days
AGE_101=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 101:
            print(pr['age_tag'])
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$AGE_101" "waiting 10d" "PR 101 age tag = waiting 10d"

# PR 108 updatedAt = 2026-09-19T10:00:00Z → 11 days
AGE_108=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 108:
            print(pr['age_tag'])
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$AGE_108" "waiting 11d" "PR 108 age tag = waiting 11d"

# PR 106 updatedAt = 2026-09-22T10:00:00Z → 8 days
AGE_106=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 106:
            print(pr['age_tag'])
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$AGE_106" "waiting 8d" "PR 106 age tag = waiting 8d"

# --- Test 11: KEY pairing ---
echo ""
echo "=== T11: KEY pairing ==="
# PR 101 headRefName "feat/SM-3008-dispatch" → SM-3008
SM3008_TICKET=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 101:
            t = group['ticket']
            print(t['key'] if t else 'NO_TICKET')
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$SM3008_TICKET" "SM-3008" "PR 101 paired to SM-3008 ticket"

# PR 105 headRefName "feat/SM-3011-feature" → SM-3011
SM3011_TICKET=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['done_new']:
    for pr in group['prs']:
        if pr['number'] == 105:
            t = group['ticket']
            print(t['key'] if t else 'NO_TICKET')
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$SM3011_TICKET" "SM-3011" "PR 105 paired to SM-3011 ticket"

# PR 108 has no KEY in branch or title → no ticket
NO_TICKET_108=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 108:
            t = group['ticket']
            print('null' if t is None else t['key'])
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$NO_TICKET_108" "null" "PR 108 (no KEY in branch/title) has no ticket"

# --- Test 12: violation — multiple PRs ---
echo ""
echo "=== T12: violation — multiple_prs ==="
MULTI_PR_KEYS=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
multi = [v['ticket_key'] for v in d['violations'] if v['type'] == 'multiple_prs']
print(sorted(multi))
")
assert_contains "$MULTI_PR_KEYS" "SM-3008" "SM-3008 flagged as multiple_prs violation"
assert_contains "$MULTI_PR_KEYS" "SM-3012" "SM-3012 flagged as multiple_prs violation"

SM3008_MULTI=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for v in d['violations']:
    if v['type'] == 'multiple_prs' and v['ticket_key'] == 'SM-3008':
        print(sorted(v['pr_numbers']))
        sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$SM3008_MULTI" "[101, 102]" "SM-3008 multiple_prs lists PR numbers [101, 102]"

# --- Test 13: violation — status disagreement ---
echo ""
echo "=== T13: violation — status_disagreement ==="
DISAGREEMENT=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
keys = [v['ticket_key'] for v in d['violations'] if v['type'] == 'status_disagreement']
print(sorted(keys))
")
assert_contains "$DISAGREEMENT" "SM-3009" "SM-3009 flagged as status_disagreement (PR merged, ticket In Progress)"

DISAGREEMENT_DETAIL=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for v in d['violations']:
    if v['type'] == 'status_disagreement' and v['ticket_key'] == 'SM-3009':
        print(v['pr_state'])
        sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$DISAGREEMENT_DETAIL" "MERGED" "status_disagreement records PR state as MERGED"

# --- Test 14: done_new vs done_earlier with standup cutoff ---
echo ""
echo "=== T14: done_new vs done_earlier split ==="
# cutoff is 2026-09-28 (from fixture standups/2026-09-28.md)
CUTOFF=$(echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['since_last_standup_cutoff'])")
assert_eq "$CUTOFF" "2026-09-28" "since_last_standup_cutoff = 2026-09-28"

# PR 105 mergedAt 2026-09-30 > cutoff 2026-09-28 → done_new
DONE_NEW_NRS=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
nums = [pr['number'] for g in d['done_new'] for pr in g['prs']]
print(sorted(nums))
")
assert_contains "$DONE_NEW_NRS" "105" "PR 105 (merged 2026-09-30) in done_new"
assert_contains "$DONE_NEW_NRS" "103" "PR 103 (merged 2026-09-29) in done_new"

# PR 109 mergedAt 2026-09-10 <= cutoff → done_earlier
DONE_EARLIER_NRS=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
nums = [pr['number'] for g in d['done_earlier'] for pr in g['prs']]
print(sorted(nums))
")
assert_contains "$DONE_EARLIER_NRS" "109" "PR 109 (merged 2026-09-10) in done_earlier"
assert_not_contains "$DONE_EARLIER_NRS" "105" "PR 105 not in done_earlier"

# --- Test 15: done_new — no standups dir (all merges go to done_new) ---
echo ""
echo "=== T15: done_new — no standups dir ==="
set +e
OUT_NO_STANDUPS=$(bash "$SCRIPT" "$LINEAR_FIXTURE" "$GITHUB_FIXTURE" 2>"$TMP/t15.err")
EXIT_NO_STANDUPS=$?
set -e

assert_exit_zero "$EXIT_NO_STANDUPS" "exits 0 with no standups dir"
assert_json_valid "$OUT_NO_STANDUPS" "output is valid JSON (no standups dir)"

CUTOFF_NONE=$(echo "$OUT_NO_STANDUPS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['since_last_standup_cutoff'])")
assert_eq "$CUTOFF_NONE" "None" "since_last_standup_cutoff is null when no standups dir"

DONE_NEW_ALL=$(echo "$OUT_NO_STANDUPS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
nums = sorted([pr['number'] for g in d['done_new'] for pr in g['prs']])
print(nums)
")
# All merged PRs (103, 105, 109) go to done_new
assert_contains "$DONE_NEW_ALL" "103" "PR 103 in done_new (no cutoff)"
assert_contains "$DONE_NEW_ALL" "105" "PR 105 in done_new (no cutoff)"
assert_contains "$DONE_NEW_ALL" "109" "PR 109 in done_new (no cutoff — all go to done_new)"

DONE_EARLIER_NONE=$(echo "$OUT_NO_STANDUPS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(len([pr for g in d['done_earlier'] for pr in g['prs']]))
")
assert_eq "$DONE_EARLIER_NONE" "0" "done_earlier is empty when no cutoff"

# --- Test 16: theme_signals fields ---
echo ""
echo "=== T16: theme_signals ==="
SIGNALS=$(echo "$OUT" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['theme_signals']))")
assert_contains "$SIGNALS" "distinct_reviewers" "theme_signals has distinct_reviewers"
assert_contains "$SIGNALS" "small_prs" "theme_signals has small_prs"
assert_contains "$SIGNALS" "ci_green_ratio" "theme_signals has ci_green_ratio"
assert_contains "$SIGNALS" "delivery_count" "theme_signals has delivery_count"

# distinct_reviewers: only "alice" reviews open non-draft PRs → 1
DR=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['theme_signals']['distinct_reviewers'])")
assert_eq "$DR" "1" "distinct_reviewers = 1 (only alice in open non-draft PRs)"

# ci_green_ratio: 4 of 6 open non-draft PRs have ci=success → 0.667
CI_RATIO=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['theme_signals']['ci_green_ratio'])")
assert_eq "$CI_RATIO" "0.667" "ci_green_ratio = 0.667 (4/6 PRs CI green)"

# delivery_count: 2 PRs in done_new (103, 105)
DC=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['theme_signals']['delivery_count'])")
assert_eq "$DC" "2" "delivery_count = 2 (PRs 103 and 105 in done_new)"

# small_prs: changedFiles <= 10 for open non-draft PRs (101:5, 102:8, 106:4, 107:6, 108:3, 110:4 → all 6)
SP=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['theme_signals']['small_prs'])")
assert_eq "$SP" "6" "small_prs = 6 (all open non-draft PRs have changedFiles <= 10)"

# --- Test 17: in_progress contains ticket with no PR ---
echo ""
echo "=== T17: in_progress — ticket with no PR ==="
SM3013_IN_PROGRESS=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_progress']:
    t = group['ticket']
    if t and t['key'] == 'SM-3013':
        print('FOUND_prs=' + str(len(group['prs'])))
        sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$SM3013_IN_PROGRESS" "FOUND_prs=0" "SM-3013 (no PR) appears in in_progress with 0 prs"

# --- Test 18: blockers contain red-bucket items ---
echo ""
echo "=== T18: blockers ==="
BLOCKER_KEYS=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
keys = []
for g in d['blockers']:
    t = g['ticket']
    k = t['key'] if t else '(no ticket)'
    for pr in g['prs']:
        keys.append(k + ':' + str(pr['number']))
print(sorted(keys))
")
assert_contains "$BLOCKER_KEYS" "SM-3008" "SM-3008 red PRs appear in blockers"
assert_contains "$BLOCKER_KEYS" "SM-3012" "SM-3012 red PR appears in blockers"

# All blocker PRs should have bucket=red
ALL_BLOCKERS_RED=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
all_red = all(pr['bucket'] == 'red'
              for g in d['blockers']
              for pr in g['prs'])
print('OK' if all_red else 'NOK')
")
assert_eq "$ALL_BLOCKERS_RED" "OK" "all blocker PRs have bucket=red"

# --- Test 19: CHANGES_REQUESTED superseded by later APPROVED ---
echo ""
echo "=== T19: CHANGES_REQUESTED superseded by APPROVED ==="
# Create a fixture where reviewer alice first CHANGES_REQUESTED then APPROVED
cat > "$TMP/gh_superseded.json" << 'EOF'
{
  "prs": [
    {
      "number": 200,
      "title": "feat: TEST-1 superseded review",
      "body": "",
      "headRefName": "feat/TEST-1-superseded",
      "state": "OPEN",
      "isDraft": false,
      "createdAt": "2026-09-25T10:00:00Z",
      "updatedAt": "2026-09-28T10:00:00Z",
      "mergedAt": null,
      "reviews": [
        {"login": "alice", "state": "CHANGES_REQUESTED"},
        {"login": "alice", "state": "APPROVED"}
      ],
      "reviewRequests": [],
      "ciRollup": "success",
      "unresolvedThreadCount": 0,
      "changedFiles": 3
    }
  ],
  "key_ids": ["TEST-1"]
}
EOF
cat > "$TMP/linear_superseded.json" << 'EOF'
[{"id": "uuid-t1", "key": "TEST-1", "title": "Superseded test", "status": "In Progress", "url": "http://x", "parentKey": null, "epicKey": null}]
EOF

set +e
OUT19=$(bash "$SCRIPT" "$TMP/linear_superseded.json" "$TMP/gh_superseded.json" 2>"$TMP/t19.err")
EXIT19=$?
set -e

assert_exit_zero "$EXIT19" "exits 0 with superseded review fixture"
BUCKET_200=$(echo "$OUT19" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 200:
            print(pr['bucket'])
            sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$BUCKET_200" "green" "PR with CHANGES_REQUESTED superseded by APPROVED → green"

# --- Test 20: error on missing input file ---
echo ""
echo "=== T20: error on missing file ==="
set +e
ERR20=$(bash "$SCRIPT" "/nonexistent/linear.json" "$GITHUB_FIXTURE" 2>&1)
EXIT20=$?
set -e
if [ "$EXIT20" -ne 0 ]; then
  assert_pass "exits non-zero when linear_json not found"
else
  assert_fail "should exit non-zero when linear_json not found (exited 0)"
fi

# --- Test 21: PR objects have url and reviewers fields ---
echo ""
echo "=== T21: PR url and reviewers passthrough ==="
# PR 101 should have url from fixture and reviewers=["alice"]
PR101_URL=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 101:
            print(pr.get('url', 'MISSING'))
            sys.exit(0)
print('NOT_FOUND')
")
assert_contains "$PR101_URL" "pull/101" "PR 101 url passed through from github fixture"

PR101_REVIEWERS=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 101:
            print(sorted(pr.get('reviewers', [])))
            sys.exit(0)
print('NOT_FOUND')
")
assert_contains "$PR101_REVIEWERS" "alice" "PR 101 reviewers includes alice"

# PR 106 reviewers=["dave"] (reviewRequests only)
PR106_REVIEWERS=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    for pr in group['prs']:
        if pr['number'] == 106:
            print(pr.get('reviewers', []))
            sys.exit(0)
print('NOT_FOUND')
")
assert_contains "$PR106_REVIEWERS" "dave" "PR 106 reviewers includes dave (from reviewRequests)"

# PR 105 (done_new) reviewers=["carol"]
PR105_REVIEWERS=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['done_new']:
    for pr in group['prs']:
        if pr['number'] == 105:
            print(pr.get('reviewers', []))
            sys.exit(0)
print('NOT_FOUND')
")
assert_contains "$PR105_REVIEWERS" "carol" "PR 105 (done_new) reviewers includes carol"

# --- Test 22: ticket objects have projectName field ---
echo ""
echo "=== T22: ticket projectName passthrough ==="
# SM-3008 has projectName="Platform Reliability"
SM3008_PROJECT=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['in_review']:
    t = group['ticket']
    if t and t.get('key') == 'SM-3008':
        print(t.get('projectName', 'MISSING'))
        sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$SM3008_PROJECT" "Platform Reliability" "SM-3008 ticket has projectName=Platform Reliability"

# SM-3009 has projectName=null
SM3009_PROJECT=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['done_new']:
    t = group['ticket']
    if t and t.get('key') == 'SM-3009':
        print(t.get('projectName'))
        sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$SM3009_PROJECT" "None" "SM-3009 ticket has projectName=null"

# SM-3011 (done_new) has projectName="Platform Reliability"
SM3011_PROJECT=$(echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for group in d['done_new']:
    t = group['ticket']
    if t and t.get('key') == 'SM-3011':
        print(t.get('projectName', 'MISSING'))
        sys.exit(0)
print('NOT_FOUND')
")
assert_eq "$SM3011_PROJECT" "Platform Reliability" "SM-3011 (done_new) ticket has projectName=Platform Reliability"

# --- Results ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
