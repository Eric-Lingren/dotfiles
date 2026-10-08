#!/usr/bin/env bash
# Tests for fetch-github-standup.sh
# Uses fixture JSON files — no real gh CLI calls are made.
#
# Usage: bash test-fetch-github-standup.sh
# Exit 0 = all tests passed. Exit 1 = one or more failed.

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPTS_DIR/standup/fetch-github-standup.sh"
FIXTURES="$(dirname "$0")/fixtures/fetch-github-standup"

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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
    assert_fail "$desc (pattern '$pattern' not found in output)"
    echo "    Actual output (first 300 chars): ${text:0:300}"
  fi
}

assert_not_contains() {
  local text="$1" pattern="$2" desc="$3"
  if echo "$text" | grep -q "$pattern"; then
    assert_fail "$desc (pattern '$pattern' unexpectedly found)"
    echo "    Actual output (first 300 chars): ${text:0:300}"
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
    echo "    Output (first 300 chars): ${text:0:300}"
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

jq_get() {
  # Extract a value from JSON using python3 instead of jq
  local json="$1" path="$2"
  echo "$json" | python3 -c "import json,sys; d=json.load(sys.stdin); print($path)"
}

# --- Test 1: script exists and is executable ---
echo "=== T1: script exists ==="
if [ -f "$SCRIPT" ]; then
  assert_pass "fetch-github-standup.sh exists"
else
  assert_fail "fetch-github-standup.sh not found at $SCRIPT"
fi
if [ -x "$SCRIPT" ]; then
  assert_pass "script is executable"
else
  assert_fail "script is not executable"
fi

# --- Test 2: exits 0 and emits valid JSON ---
echo ""
echo "=== T2: exit 0 and valid JSON ==="
set +e
OUT2=$(GH_PR_LIST_FIXTURE="$FIXTURES/pr-list.json" \
       GH_PR_THREADS_FIXTURE="$FIXTURES/threads.json" \
       bash "$SCRIPT" 2>"$TMP/t2.err")
EXIT2=$?
set -e

assert_exit_zero "$EXIT2" "exits 0 with fixture inputs"
assert_json_valid "$OUT2" "output is valid JSON"

# --- Test 3: output has prs array and key_ids array ---
echo ""
echo "=== T3: output shape ==="
PRS_TYPE=$(echo "$OUT2" | python3 -c "import json,sys; d=json.load(sys.stdin); print(type(d.get('prs')).__name__)")
assert_pass "prs field present"
if [ "$PRS_TYPE" = "list" ]; then
  assert_pass "prs is an array"
else
  assert_fail "prs should be array, got $PRS_TYPE"
fi

KEY_IDS_TYPE=$(echo "$OUT2" | python3 -c "import json,sys; d=json.load(sys.stdin); print(type(d.get('key_ids')).__name__)")
if [ "$KEY_IDS_TYPE" = "list" ]; then
  assert_pass "key_ids is an array"
else
  assert_fail "key_ids should be array, got $KEY_IDS_TYPE"
fi

# --- Test 4: PR object shape ---
echo ""
echo "=== T4: PR object shape ==="
FIELDS_CHECK=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
prs = d.get('prs', [])
required = ['number','title','body','headRefName','url','state','isDraft',
            'createdAt','updatedAt','mergedAt','reviews','reviewRequests',
            'reviewers','ciRollup','unresolvedThreadCount']
pr = prs[0]
missing = [f for f in required if f not in pr]
if missing:
    print('MISSING: ' + ', '.join(missing))
else:
    print('OK')
")
if [ "$FIELDS_CHECK" = "OK" ]; then
  assert_pass "all required PR fields present in first PR"
else
  assert_fail "PR object missing fields: $FIELDS_CHECK"
fi

# --- Test 5: reviews have login and state ---
echo ""
echo "=== T5: reviews shape ==="
REVIEW_CHECK=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = d['prs'][0]
reviews = pr.get('reviews', [])
if len(reviews) < 2:
    print('NOT_ENOUGH')
    sys.exit(0)
ok = all('login' in r and 'state' in r for r in reviews)
print('OK' if ok else 'BAD_SHAPE')
")
if [ "$REVIEW_CHECK" = "OK" ]; then
  assert_pass "reviews have login and state fields"
else
  assert_fail "reviews shape check failed: $REVIEW_CHECK"
fi

# --- Test 6: reviewRequests is an array of login strings ---
echo ""
echo "=== T6: reviewRequests ==="
RR_CHECK=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = d['prs'][0]
rr = pr.get('reviewRequests', [])
if not isinstance(rr, list):
    print('NOT_LIST')
    sys.exit(0)
if len(rr) > 0 and not isinstance(rr[0], str):
    print('NOT_STRINGS')
    sys.exit(0)
print('OK')
")
if [ "$RR_CHECK" = "OK" ]; then
  assert_pass "reviewRequests is array of login strings"
else
  assert_fail "reviewRequests check failed: $RR_CHECK"
fi

# Check it contains 'carol'
assert_contains "$OUT2" '"carol"' "reviewRequests contains requested reviewer carol"

# --- Test 6b: url field present ---
echo ""
echo "=== T6b: url field ==="
URL_CHECK=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
prs = d.get('prs', [])
for pr in prs:
    if 'url' not in pr:
        print('MISSING_URL on PR ' + str(pr['number']))
        sys.exit(0)
print('OK')
")
if [ "$URL_CHECK" = "OK" ]; then
  assert_pass "url field present on all PR objects"
else
  assert_fail "url field check failed: $URL_CHECK"
fi

# PR 101 url
PR101_URL=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = next(p for p in d['prs'] if p['number'] == 101)
print(pr['url'])
")
assert_contains "$PR101_URL" "pull/101" "PR 101 url contains pull/101"

# --- Test 6c: reviewers field ---
echo ""
echo "=== T6c: reviewers field ==="
REVIEWERS_CHECK=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
prs = d.get('prs', [])
for pr in prs:
    if 'reviewers' not in pr:
        print('MISSING_reviewers on PR ' + str(pr['number']))
        sys.exit(0)
    if not isinstance(pr['reviewers'], list):
        print('NOT_LIST on PR ' + str(pr['number']))
        sys.exit(0)
print('OK')
")
if [ "$REVIEWERS_CHECK" = "OK" ]; then
  assert_pass "reviewers field present and is list on all PRs"
else
  assert_fail "reviewers field check failed: $REVIEWERS_CHECK"
fi

# PR 101 has reviews from alice and bob, plus reviewRequest for carol
PR101_REVIEWERS=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = next(p for p in d['prs'] if p['number'] == 101)
print(sorted(pr['reviewers']))
")
assert_contains "$PR101_REVIEWERS" "alice" "PR 101 reviewers includes alice"
assert_contains "$PR101_REVIEWERS" "bob" "PR 101 reviewers includes bob"
assert_contains "$PR101_REVIEWERS" "carol" "PR 101 reviewers includes carol (from reviewRequests)"

# PR 102 has only alice as reviewer
PR102_REVIEWERS=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = next(p for p in d['prs'] if p['number'] == 102)
print(pr['reviewers'])
")
assert_eq "$PR102_REVIEWERS" "['alice']" "PR 102 reviewers = ['alice']"

# PR 103 (draft) has no reviewers
PR103_REVIEWERS=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = next(p for p in d['prs'] if p['number'] == 103)
print(pr['reviewers'])
")
assert_eq "$PR103_REVIEWERS" "[]" "PR 103 (draft, no reviews) reviewers = []"

# --- Test 7: ciRollup values ---
echo ""
echo "=== T7: ciRollup states ==="
CI_ROLLUPS=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
valid = {'success', 'failure', 'pending', 'none'}
for pr in d['prs']:
    rollup = pr.get('ciRollup', '')
    if rollup not in valid:
        print('INVALID:' + rollup)
        sys.exit(0)
print('OK')
")
if [ "$CI_ROLLUPS" = "OK" ]; then
  assert_pass "all ciRollup values are valid (success/failure/pending/none)"
else
  assert_fail "ciRollup has invalid value: $CI_ROLLUPS"
fi

# PR 101: both checks SUCCESS -> should be "success"
PR101_ROLLUP=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = next(p for p in d['prs'] if p['number'] == 101)
print(pr['ciRollup'])
")
if [ "$PR101_ROLLUP" = "success" ]; then
  assert_pass "PR 101 ciRollup=success (all checks passed)"
else
  assert_fail "PR 101 ciRollup expected 'success', got '$PR101_ROLLUP'"
fi

# PR 102: FAILURE check -> "failure"
PR102_ROLLUP=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = next(p for p in d['prs'] if p['number'] == 102)
print(pr['ciRollup'])
")
if [ "$PR102_ROLLUP" = "failure" ]; then
  assert_pass "PR 102 ciRollup=failure (one check failed)"
else
  assert_fail "PR 102 ciRollup expected 'failure', got '$PR102_ROLLUP'"
fi

# PR 103: IN_PROGRESS check -> "pending"
PR103_ROLLUP=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = next(p for p in d['prs'] if p['number'] == 103)
print(pr['ciRollup'])
")
if [ "$PR103_ROLLUP" = "pending" ]; then
  assert_pass "PR 103 ciRollup=pending (check in progress)"
else
  assert_fail "PR 103 ciRollup expected 'pending', got '$PR103_ROLLUP'"
fi

# PR 104: empty checks -> "none"
PR104_ROLLUP=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = next(p for p in d['prs'] if p['number'] == 104)
print(pr['ciRollup'])
")
if [ "$PR104_ROLLUP" = "none" ]; then
  assert_pass "PR 104 ciRollup=none (no checks)"
else
  assert_fail "PR 104 ciRollup expected 'none', got '$PR104_ROLLUP'"
fi

# --- Test 8: unresolvedThreadCount is numeric ---
echo ""
echo "=== T8: unresolvedThreadCount ==="
THREAD_CHECK=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for pr in d['prs']:
    v = pr.get('unresolvedThreadCount')
    if not isinstance(v, int):
        print('NOT_INT:' + str(v) + ' on PR ' + str(pr['number']))
        sys.exit(0)
print('OK')
")
if [ "$THREAD_CHECK" = "OK" ]; then
  assert_pass "unresolvedThreadCount is integer on all PRs"
else
  assert_fail "unresolvedThreadCount check failed: $THREAD_CHECK"
fi

PR101_THREADS=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = next(p for p in d['prs'] if p['number'] == 101)
print(pr['unresolvedThreadCount'])
")
if [ "$PR101_THREADS" = "3" ]; then
  assert_pass "PR 101 unresolvedThreadCount=3 (from fixture)"
else
  assert_fail "PR 101 unresolvedThreadCount expected 3, got '$PR101_THREADS'"
fi

PR102_THREADS=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
pr = next(p for p in d['prs'] if p['number'] == 102)
print(pr['unresolvedThreadCount'])
")
if [ "$PR102_THREADS" = "0" ]; then
  assert_pass "PR 102 unresolvedThreadCount=0"
else
  assert_fail "PR 102 unresolvedThreadCount expected 0, got '$PR102_THREADS'"
fi

# --- Test 9: KEY id extraction from branch names ---
echo ""
echo "=== T9: KEY extraction from branch names ==="
KEY_IDS=$(echo "$OUT2" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['key_ids'])")

# PR 101 has headRefName "feat/SM-3008-dispatch"
assert_contains "$KEY_IDS" "SM-3008" "SM-3008 extracted from branch name"

# PR 101 title has "SM-3008 dispatch redesign"
# SM-3008 already covered above; SM-3010 is only in body (not extracted)

# PR 102 title has KEY-42
assert_contains "$KEY_IDS" "KEY-42" "KEY-42 extracted from PR title"

# chore PR has no KEY
assert_not_contains "$KEY_IDS" "chore" "chore prefix not treated as KEY id"

# --- Test 10: KEY extraction from PR titles ---
echo ""
echo "=== T10: KEY extraction from titles (multi-key fixture) ==="
set +e
OUT10=$(GH_PR_LIST_FIXTURE="$FIXTURES/pr-list-key-extraction.json" \
        GH_PR_THREADS_FIXTURE="$FIXTURES/threads-empty.json" \
        bash "$SCRIPT" 2>"$TMP/t10.err")
EXIT10=$?
set -e

assert_exit_zero "$EXIT10" "exits 0 with key extraction fixture"
assert_json_valid "$OUT10" "key extraction fixture output is valid JSON"

KEY_IDS10=$(echo "$OUT10" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted(d['key_ids']))")

# PR 201 title: "Add PROJ-100 and PROJ-200 to pipeline" + branch "feat/MYTEAM-999-new-feature"
assert_contains "$KEY_IDS10" "PROJ-100" "PROJ-100 extracted from title"
assert_contains "$KEY_IDS10" "PROJ-200" "PROJ-200 extracted from title"
assert_contains "$KEY_IDS10" "MYTEAM-999" "MYTEAM-999 extracted from branch name"

# PR 202: no KEY ids -> key_ids should not include random words
PR202_KEYS=$(echo "$OUT10" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d['key_ids'])
")
# Should have exactly MYTEAM-999, PROJ-100, PROJ-200
KEY_COUNT=$(echo "$OUT10" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(len(d['key_ids']))
")
if [ "$KEY_COUNT" = "3" ]; then
  assert_pass "key_ids has exactly 3 entries (deduped)"
else
  assert_fail "key_ids expected 3 entries, got $KEY_COUNT: $PR202_KEYS"
fi

# --- Test 11: key_ids are deduplicated ---
echo ""
echo "=== T11: key_ids deduplication ==="
# SM-3008 appears in both branch AND title of PR 101
# It should appear only once
SM3008_COUNT=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d['key_ids'].count('SM-3008'))
")
if [ "$SM3008_COUNT" = "1" ]; then
  assert_pass "SM-3008 appears exactly once in key_ids (deduplicated)"
else
  assert_fail "SM-3008 dedup failed, count=$SM3008_COUNT"
fi

# --- Test 12: key_ids are sorted ---
echo ""
echo "=== T12: key_ids are sorted ==="
SORTED_CHECK=$(echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
k = d['key_ids']
print('OK' if k == sorted(k) else 'NOT_SORTED: ' + str(k))
")
if [ "$SORTED_CHECK" = "OK" ]; then
  assert_pass "key_ids array is sorted"
else
  assert_fail "key_ids not sorted: $SORTED_CHECK"
fi

# --- Test 13: prs array length matches fixture ---
echo ""
echo "=== T13: prs count ==="
PRS_COUNT=$(echo "$OUT2" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['prs']))")
if [ "$PRS_COUNT" = "4" ]; then
  assert_pass "prs array has 4 entries (matching fixture)"
else
  assert_fail "prs array expected 4 entries, got $PRS_COUNT"
fi

# --- Test 14: unresolvedThreadCount defaults to 0 when PR not in threads map ---
echo ""
echo "=== T14: unresolvedThreadCount defaults to 0 ==="
set +e
OUT14=$(GH_PR_LIST_FIXTURE="$FIXTURES/pr-list.json" \
        GH_PR_THREADS_FIXTURE="$FIXTURES/threads-empty.json" \
        bash "$SCRIPT" 2>"$TMP/t14.err")
EXIT14=$?
set -e

assert_exit_zero "$EXIT14" "exits 0 with empty threads fixture"

THREAD_ALL_ZERO=$(echo "$OUT14" | python3 -c "
import json, sys
d = json.load(sys.stdin)
all_zero = all(p['unresolvedThreadCount'] == 0 for p in d['prs'])
print('OK' if all_zero else 'NONZERO')
")
if [ "$THREAD_ALL_ZERO" = "OK" ]; then
  assert_pass "all unresolvedThreadCounts default to 0 when not in threads map"
else
  assert_fail "some unresolvedThreadCounts were non-zero with empty threads map"
fi

# --- Test 15: reviewDecision passes through, null when absent ---
echo ""
echo "=== T15: reviewDecision passthrough ==="
DECISIONS=$(echo "$OUT14" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(' '.join(f\"{p['number']}={p['reviewDecision']}\" for p in d['prs'][:2]))
")
assert_eq "$DECISIONS" "101=CHANGES_REQUESTED 102=None" "reviewDecision copied from gh, None when missing"

# --- Results ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
