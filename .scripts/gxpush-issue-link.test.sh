#!/usr/bin/env bash
# gxpush-issue-link.test.sh — Unit tests for the Closes #N PR-body injection logic
# Tests the logic in isolation using a helper function that mirrors gxpush's implementation.
#
# Usage: bash .scripts/gxpush-issue-link.test.sh
# Exit 0 = all pass, non-zero = failures present

set -uo pipefail

PASS=0
FAIL=0

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label"
    echo "    expected to contain: $needle"
    echo "    actual body: $haystack"
    FAIL=$((FAIL+1))
  fi
}

assert_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label"
    echo "    expected NOT to contain: $needle"
    echo "    actual body: $haystack"
    FAIL=$((FAIL+1))
  fi
}

# Mirror the exact logic that will be added to gxpush.
# Args: BRANCH_SLUG PR_BODY [GITHUB_CLOSES override]
resolve_closes_suffix() {
  local branch_slug="$1"
  local pr_body="$2"
  local closes_env="${GITHUB_CLOSES:-}"

  local issue_number=""
  if [[ -n "$closes_env" ]]; then
    issue_number="$closes_env"
  else
    # Extract gh-NNN from branch slug
    if [[ "$branch_slug" =~ gh-([0-9]+) ]]; then
      issue_number="${BASH_REMATCH[1]}"
    fi
  fi

  if [[ -n "$issue_number" ]]; then
    printf '%s\n\nCloses #%s' "$pr_body" "$issue_number"
  else
    printf '%s' "$pr_body"
  fi
}

BASE_BODY="This PR does something useful."

echo "=== gxpush issue-link logic tests ==="
echo ""

# --- Test 1: GITHUB_CLOSES env var is set ---
echo "1. GITHUB_CLOSES=42 signal"
RESULT=$(GITHUB_CLOSES=42 resolve_closes_suffix "some-branch" "$BASE_BODY")
assert_contains "body contains 'Closes #42'" "$RESULT" "Closes #42"
assert_not_contains "body does not contain 'Closes #43'" "$RESULT" "Closes #43"
echo ""

# --- Test 2: Branch name contains gh-42 ---
echo "2. Branch name gh-42 fallback"
RESULT=$(unset GITHUB_CLOSES; resolve_closes_suffix "feat-gh-42-add-widget" "$BASE_BODY")
assert_contains "body contains 'Closes #42'" "$RESULT" "Closes #42"
echo ""

# --- Test 3: Both signals present — env var takes precedence ---
echo "3. Both signals: GITHUB_CLOSES=99 + branch gh-42 → env wins"
RESULT=$(GITHUB_CLOSES=99 resolve_closes_suffix "feat-gh-42-add-widget" "$BASE_BODY")
assert_contains "body contains 'Closes #99'" "$RESULT" "Closes #99"
assert_not_contains "body does NOT contain 'Closes #42'" "$RESULT" "Closes #42"
echo ""

# --- Test 4: Neither signal present — body unchanged ---
echo "4. No signal — body unchanged"
RESULT=$(unset GITHUB_CLOSES; resolve_closes_suffix "feat-add-widget" "$BASE_BODY")
assert_not_contains "body does not contain 'Closes'" "$RESULT" "Closes"
# Body should be exactly unchanged
if [[ "$RESULT" == "$BASE_BODY" ]]; then
  echo "  PASS: body is byte-for-byte identical to input"
  ((PASS++))
else
  echo "  FAIL: body was modified unexpectedly"
  echo "    expected: $BASE_BODY"
  echo "    actual:   $RESULT"
  ((FAIL++))
fi
echo ""

# --- Test 5: Branch with gh- but no digits — no match ---
echo "5. Branch 'gh-no-digits' — no match"
RESULT=$(unset GITHUB_CLOSES; resolve_closes_suffix "gh-no-digits" "$BASE_BODY")
assert_not_contains "body unchanged (no digits after gh-)" "$RESULT" "Closes"
echo ""

# --- Test 6: GITHUB_CLOSES is set to empty string — should fall through to branch check ---
echo "6. GITHUB_CLOSES='' + branch gh-7 — branch fallback wins"
RESULT=$(GITHUB_CLOSES="" resolve_closes_suffix "gh-7-fix-thing" "$BASE_BODY")
assert_contains "body contains 'Closes #7'" "$RESULT" "Closes #7"
echo ""

# --- Test 7: Closes #N appears after double newline ---
echo "7. Closes #N appears after double newline"
RESULT=$(GITHUB_CLOSES=5 resolve_closes_suffix "branch" "$BASE_BODY")
if printf '%s' "$RESULT" | grep -qF $'\n\nCloses #5'; then
  echo "  PASS: 'Closes #5' follows double newline"
  ((PASS++))
else
  echo "  FAIL: expected double newline before 'Closes #5'"
  echo "    actual body (escaped): $(printf '%s' "$RESULT" | cat -A)"
  ((FAIL++))
fi
echo ""

# --- Summary ---
echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
