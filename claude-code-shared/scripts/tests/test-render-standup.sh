#!/usr/bin/env bash
# Tests for render-standup.sh
# Uses fixture JSON files — no real API calls are made.
# This is the full dry-run test that exercises the complete render pipeline.
#
# Usage: bash test-render-standup.sh
# Exit 0 = all tests passed. Exit 1 = one or more failed.

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPTS_DIR/standup/render-standup.sh"
FIXTURES="$(dirname "$0")/fixtures/standup"

DATA_FIXTURE="$FIXTURES/data.json"
PROSE_FIXTURE="$FIXTURES/prose.json"

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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
  else
    assert_pass "$desc"
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

# --- Test 1: script exists and is executable ---
echo "=== T1: script exists ==="
if [ -f "$SCRIPT" ]; then
  assert_pass "render-standup.sh exists"
else
  assert_fail "render-standup.sh not found at $SCRIPT"
fi
if [ -x "$SCRIPT" ]; then
  assert_pass "render-standup.sh is executable"
else
  assert_fail "render-standup.sh is not executable"
fi

# --- Test 2: full dry-run with fixtures ---
echo ""
echo "=== T2: full dry-run produces output ==="
set +e
OUT=$(bash "$SCRIPT" "$DATA_FIXTURE" "$PROSE_FIXTURE" 2>"$TMP/t2.err")
EXIT2=$?
set -e

assert_exit_zero "$EXIT2" "exits 0 with fixture inputs"

if [ -n "$OUT" ]; then
  assert_pass "output is non-empty"
else
  assert_fail "output is empty"
  echo "  stderr: $(cat "$TMP/t2.err")"
fi

# --- Test 3: all six sections present ---
echo ""
echo "=== T3: all six sections present ==="
assert_contains "$OUT" "## In Review" "output contains ## In Review section"
assert_contains "$OUT" "## Done" "output contains ## Done section"
assert_contains "$OUT" "## In Progress" "output contains ## In Progress section"
assert_contains "$OUT" "## Blockers" "output contains ## Blockers section"
assert_contains "$OUT" "## Theme" "output contains ## Theme section"
assert_contains "$OUT" "## Talk track" "output contains ## Talk track section"

# --- Test 4: In Review section content ---
echo ""
echo "=== T4: In Review content ==="
# Should include PR 101 and SM-3008 ticket
assert_contains "$OUT" "SM-3008" "In Review contains SM-3008"
assert_contains "$OUT" "pull/101" "In Review contains PR 101 link"
assert_contains "$OUT" "🟡" "In Review yellow bucket emoji present"
assert_contains "$OUT" "alice" "In Review shows reviewer alice"
assert_contains "$OUT" "waiting 10d" "In Review shows age tag"

# --- Test 5: Done section content ---
echo ""
echo "=== T5: Done section content ==="
# SM-3011 was merged after cutoff → done_new with 🆕
assert_contains "$OUT" "🆕" "Done section has 🆕 new tag"
assert_contains "$OUT" "SM-3011" "Done section contains SM-3011"
assert_contains "$OUT" "pull/105" "Done section contains PR 105 link"

# --- Test 6: In Progress section content ---
echo ""
echo "=== T6: In Progress content ==="
assert_contains "$OUT" "SM-3013" "In Progress contains SM-3013"
assert_contains "$OUT" "no PR yet" "In Progress shows (no PR yet) tag"

# --- Test 7: Blockers section present (empty) ---
echo ""
echo "=== T7: Blockers section ==="
# No blockers in fixture → should say (none)
assert_contains "$OUT" "## Blockers" "Blockers section header present"
assert_contains "$OUT" "none" "Blockers shows (none) when empty"

# --- Test 8: Theme section content ---
echo ""
echo "=== T8: Theme content ==="
assert_contains "$OUT" "Steady delivery" "Theme section contains prose theme"

# --- Test 9: Talk track format ---
echo ""
echo "=== T9: Talk track content ==="
assert_contains "$OUT" "> Merged Feature X" "Talk track line 1 starts with >"
assert_contains "$OUT" "> Dispatch redesign" "Talk track line 2 present"
assert_contains "$OUT" "> Next:" "Talk track line 3 (next) present"
# Talk track lines are quoted with >
TALK_LINES=$(echo "$OUT" | grep -c "^>" || true)
if [ "$TALK_LINES" -ge 3 ] && [ "$TALK_LINES" -le 4 ]; then
  assert_pass "talk track has 3-4 quoted lines"
else
  assert_fail "talk track should have 3-4 lines starting with >, got $TALK_LINES"
fi

# --- Test 10: summaries are used ---
echo ""
echo "=== T10: prose summaries injected ==="
assert_contains "$OUT" "deterministic event loop" "SM-3008 summary text included"
assert_contains "$OUT" "user-facing feature X" "SM-3011 summary text included"

# --- Test 11: talk track word count validation ---
echo ""
echo "=== T11: talk track over-60-word validation ==="
# Create a prose fixture with a talk track over 60 words
cat > "$TMP/prose_too_long.json" << 'EOF'
{
  "summaries": {},
  "theme": "Theme sentence.",
  "talk_track": [
    "This is an extremely long first line that contains many many many many many many extra words to help push us well over the sixty word total limit.",
    "This is a second extremely long line with many many many many many many extra words that pushes us even further over the absolute limit.",
    "And this third exceedingly long line ensures we are definitively and absolutely well over sixty total words in the entire talk track section here."
  ]
}
EOF
set +e
OUT11=$(bash "$SCRIPT" "$DATA_FIXTURE" "$TMP/prose_too_long.json" 2>"$TMP/t11.err")
EXIT11=$?
set -e
if [ "$EXIT11" -ne 0 ]; then
  assert_pass "exits non-zero when talk track exceeds 60 words"
else
  assert_fail "should exit non-zero when talk track over 60 words (got exit 0)"
fi
if grep -q "60 words" "$TMP/t11.err" 2>/dev/null; then
  assert_pass "error message mentions 60 words"
else
  assert_fail "error message should mention 60 words. stderr: $(cat "$TMP/t11.err")"
fi

# --- Test 12: talk track line count validation ---
echo ""
echo "=== T12: talk track line count validation ==="
# 2 lines → should fail
cat > "$TMP/prose_2lines.json" << 'EOF'
{
  "summaries": {},
  "theme": "Theme.",
  "talk_track": [
    "Line one.",
    "Line two."
  ]
}
EOF
set +e
OUT12=$(bash "$SCRIPT" "$DATA_FIXTURE" "$TMP/prose_2lines.json" 2>"$TMP/t12.err")
EXIT12=$?
set -e
if [ "$EXIT12" -ne 0 ]; then
  assert_pass "exits non-zero when talk track has 2 lines"
else
  assert_fail "should exit non-zero for 2-line talk track"
fi

# 5 lines → should fail
cat > "$TMP/prose_5lines.json" << 'EOF'
{
  "summaries": {},
  "theme": "Theme.",
  "talk_track": [
    "Line 1.",
    "Line 2.",
    "Line 3.",
    "Line 4.",
    "Line 5 extra line."
  ]
}
EOF
set +e
OUT12b=$(bash "$SCRIPT" "$DATA_FIXTURE" "$TMP/prose_5lines.json" 2>"$TMP/t12b.err")
EXIT12b=$?
set -e
if [ "$EXIT12b" -ne 0 ]; then
  assert_pass "exits non-zero when talk track has 5 lines"
else
  assert_fail "should exit non-zero for 5-line talk track"
fi

# --- Test 13: done_earlier renders as one-liner ---
echo ""
echo "=== T13: done_earlier one-liner ==="
# Create a data fixture with both done_new and done_earlier
cat > "$TMP/data_with_earlier.json" << 'EOF'
{
  "in_review": [],
  "done_new": [
    {
      "ticket": {"key": "SM-3011", "title": "Feature X", "status": "Done",
                 "url": "https://linear.app/sm/issue/SM-3011",
                 "parentKey": null, "epicKey": null, "projectName": null},
      "prs": [{"number": 105, "title": "feat: SM-3011",
               "headRefName": "feat/SM-3011", "url": "https://github.com/owner/repo/pull/105",
               "state": "MERGED", "ciRollup": "success", "unresolvedThreadCount": 0,
               "changedFiles": 7, "createdAt": "2026-09-30T10:00:00Z",
               "updatedAt": "2026-09-30T10:00:00Z", "mergedAt": "2026-09-30T10:00:00Z",
               "age_tag": "waiting 0d", "reviewers": ["carol"]}]
    }
  ],
  "done_earlier": [
    {
      "ticket": {"key": "SM-3009", "title": "Old fix", "status": "Done",
                 "url": "https://linear.app/sm/issue/SM-3009",
                 "parentKey": null, "epicKey": null, "projectName": null},
      "prs": [{"number": 103, "title": "fix: SM-3009",
               "headRefName": "fix/SM-3009", "url": "https://github.com/owner/repo/pull/103",
               "state": "MERGED", "ciRollup": "success", "unresolvedThreadCount": 0,
               "changedFiles": 3, "createdAt": "2026-09-10T10:00:00Z",
               "updatedAt": "2026-09-10T10:00:00Z", "mergedAt": "2026-09-10T10:00:00Z",
               "age_tag": "waiting 20d", "reviewers": ["bob"]}]
    }
  ],
  "in_progress": [],
  "blockers": [],
  "theme_signals": {"distinct_reviewers": 1, "small_prs": 1, "ci_green_ratio": 1.0, "delivery_count": 1},
  "violations": [],
  "since_last_standup_cutoff": "2026-09-28"
}
EOF

set +e
OUT13=$(bash "$SCRIPT" "$TMP/data_with_earlier.json" "$PROSE_FIXTURE" 2>"$TMP/t13.err")
EXIT13=$?
set -e

assert_exit_zero "$EXIT13" "exits 0 with done_earlier fixture"
assert_contains "$OUT13" "Earlier this cycle" "Done section has 'Earlier this cycle' one-liner"
assert_contains "$OUT13" "SM-3009" "Earlier this cycle line contains SM-3009 link"

# --- Test 14: violations render inline ---
echo ""
echo "=== T14: violations inline ==="
cat > "$TMP/data_violations.json" << 'EOF'
{
  "in_review": [
    {
      "ticket": {"key": "SM-3008", "title": "Multi-PR",
                 "url": "https://linear.app/sm/issue/SM-3008", "status": "In Progress",
                 "parentKey": null, "epicKey": null, "projectName": null},
      "prs": [
        {"number": 101, "title": "PR 1", "headRefName": "feat/SM-3008-a",
         "url": "https://github.com/owner/repo/pull/101", "state": "OPEN",
         "ciRollup": "success", "unresolvedThreadCount": 0, "changedFiles": 3,
         "createdAt": "2026-09-20T10:00:00Z", "updatedAt": "2026-09-20T10:00:00Z",
         "mergedAt": null, "age_tag": "waiting 10d", "bucket": "yellow", "reviewers": []},
        {"number": 102, "title": "PR 2", "headRefName": "feat/SM-3008-b",
         "url": "https://github.com/owner/repo/pull/102", "state": "OPEN",
         "ciRollup": "success", "unresolvedThreadCount": 0, "changedFiles": 2,
         "createdAt": "2026-09-21T10:00:00Z", "updatedAt": "2026-09-21T10:00:00Z",
         "mergedAt": null, "age_tag": "waiting 9d", "bucket": "yellow", "reviewers": []}
      ]
    }
  ],
  "done_new": [],
  "done_earlier": [],
  "in_progress": [],
  "blockers": [],
  "theme_signals": {"distinct_reviewers": 0, "small_prs": 2, "ci_green_ratio": 1.0, "delivery_count": 0},
  "violations": [
    {"type": "multiple_prs", "ticket_key": "SM-3008", "pr_numbers": [101, 102]}
  ],
  "since_last_standup_cutoff": null
}
EOF

set +e
OUT14=$(bash "$SCRIPT" "$TMP/data_violations.json" "$PROSE_FIXTURE" 2>"$TMP/t14.err")
EXIT14=$?
set -e

assert_exit_zero "$EXIT14" "exits 0 with violations fixture"
assert_contains "$OUT14" "⚠️" "violations render ⚠️ marker"
assert_contains "$OUT14" "multiple PRs" "violation type shown inline"

# --- Test 15: missing input files ---
echo ""
echo "=== T15: error on missing files ==="
set +e
bash "$SCRIPT" "/nonexistent/data.json" "$PROSE_FIXTURE" 2>"$TMP/t15.err"
EXIT15=$?
set -e
if [ "$EXIT15" -ne 0 ]; then
  assert_pass "exits non-zero when data_json not found"
else
  assert_fail "should fail when data_json missing"
fi

# --- Results ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
