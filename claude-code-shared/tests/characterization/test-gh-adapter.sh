#!/usr/bin/env bash
# Characterization tests for the export-tasks-gh adapter (gh-issue.sh).
# These tests capture argument-validation behavior only — no real gh CLI calls.
# After the move to agents/egress/github/, update GH_SCRIPT path below.
#
# Usage: bash test-gh-adapter.sh
# Exit 0 = all tests passed. Exit 1 = one or more failed.

set -uo pipefail

# ---- script under test -------------------------------------------------------
GH_SCRIPT="$HOME/.dotfiles/claude-code-shared/agents/egress/github/gh-issue.sh"

# ---- harness -----------------------------------------------------------------
PASS=0
FAIL=0

assert_exit_nonzero() {
  local exit_code="$1"
  local desc="$2"
  if [ "$exit_code" -ne 0 ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected non-zero exit, got 0)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local text="$1"
  local pattern="$2"
  local desc="$3"
  if echo "$text" | grep -qi "$pattern"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found)"
    echo "    Actual output: $text"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local path="$1"
  local desc="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== export-tasks-gh characterization tests ==="
echo ""

# Test 1: script exists at expected location
echo "-- file existence --"
assert_file_exists "$GH_SCRIPT" "gh-issue.sh exists at adapter location"
echo ""

# Test 2: no arguments → exits non-zero with usage on stderr
echo "-- argument validation --"
stderr_no_args=$(bash "$GH_SCRIPT" 2>&1 >/dev/null) || true
exit_no_args=$?
# capture exit code properly
bash "$GH_SCRIPT" > /dev/null 2>&1; exit_no_args=$?
stderr_no_args=$(bash "$GH_SCRIPT" 2>&1 || true)
assert_exit_nonzero "$exit_no_args" "exits non-zero when called with no args"
assert_contains "$stderr_no_args" "usage:" "stderr contains 'usage:' hint when called with no args"

# Test 3: fewer than 3 arguments → exits non-zero
bash "$GH_SCRIPT" "title-only" > /dev/null 2>&1; exit_one_arg=$?
assert_exit_nonzero "$exit_one_arg" "exits non-zero with only 1 argument"

bash "$GH_SCRIPT" "title" "body" > /dev/null 2>&1; exit_two_args=$?
assert_exit_nonzero "$exit_two_args" "exits non-zero with only 2 arguments"

# Test 4: empty title → exits non-zero with error
bash "$GH_SCRIPT" "" "body" "org/repo" > /dev/null 2>&1; exit_empty_title=$?
stderr_empty=$(bash "$GH_SCRIPT" "" "body" "org/repo" 2>&1 || true)
assert_exit_nonzero "$exit_empty_title" "exits non-zero when title is empty string"
assert_contains "$stderr_empty" "error:" "stderr contains 'error:' when title is empty"

# Test 5: empty body → exits non-zero
bash "$GH_SCRIPT" "title" "" "org/repo" > /dev/null 2>&1; exit_empty_body=$?
assert_exit_nonzero "$exit_empty_body" "exits non-zero when body is empty string"

# Test 6: empty repo → exits non-zero
bash "$GH_SCRIPT" "title" "body" "" > /dev/null 2>&1; exit_empty_repo=$?
assert_exit_nonzero "$exit_empty_repo" "exits non-zero when repo is empty string"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
