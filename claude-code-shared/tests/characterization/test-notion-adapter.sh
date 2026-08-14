#!/usr/bin/env bash
# Characterization tests for the export-tasks-notion adapter scripts.
# Tests check-token.sh (env var presence) and notion-page-api.sh (arg validation).
# No real Notion API calls are made.
# After the move to agents/egress/notion/, update the path variables below.
#
# Usage: bash test-notion-adapter.sh
# Exit 0 = all tests passed. Exit 1 = one or more failed.

set -uo pipefail

# ---- scripts under test ------------------------------------------------------
NOTION_DIR="$HOME/.dotfiles/claude-code-shared/agents/egress/notion"
CHECK_TOKEN_SCRIPT="$NOTION_DIR/check-token.sh"
API_SCRIPT="$NOTION_DIR/notion-page-api.sh"

# ---- harness -----------------------------------------------------------------
PASS=0
FAIL=0

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local desc="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

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

echo "=== export-tasks-notion characterization tests ==="
echo ""

# --- file existence ---
echo "-- file existence --"
assert_file_exists "$CHECK_TOKEN_SCRIPT" "check-token.sh exists at adapter location"
assert_file_exists "$API_SCRIPT" "notion-page-api.sh exists at adapter location"
echo ""

# --- check-token.sh behavior ---
echo "-- check-token.sh: NOTION_PERSONAL_TOKEN absent --"
# check-token.sh sources $HOME/.dotfiles/local/secrets.env, so we must use a
# temp HOME to prevent the real secrets from being loaded:
FAKE_HOME=$(mktemp -d)
exit_no_token=0
stderr_no_token=$(HOME="$FAKE_HOME" bash "$CHECK_TOKEN_SCRIPT" 2>&1) || exit_no_token=$?
rm -rf "$FAKE_HOME"
assert_exit_nonzero "$exit_no_token" "check-token.sh exits non-zero when NOTION_PERSONAL_TOKEN is not set"
assert_contains "$stderr_no_token" "NOTION_PERSONAL_TOKEN" "check-token.sh stderr mentions NOTION_PERSONAL_TOKEN when missing"
echo ""

echo "-- check-token.sh: NOTION_PERSONAL_TOKEN present --"
exit_with_token=0
NOTION_PERSONAL_TOKEN="ntn_fake_token_for_test" bash "$CHECK_TOKEN_SCRIPT" > /dev/null 2>&1 || exit_with_token=$?
assert_exit_code 0 "$exit_with_token" "check-token.sh exits 0 when NOTION_PERSONAL_TOKEN is set"
echo ""

# --- notion-page-api.sh argument validation ---
echo "-- notion-page-api.sh: argument validation (no API calls made) --"
# No args
bash "$API_SCRIPT" > /dev/null 2>&1; exit_no_args=$?
stderr_no_args=$(bash "$API_SCRIPT" 2>&1 || true)
assert_exit_nonzero "$exit_no_args" "notion-page-api.sh exits non-zero with no args"
assert_contains "$stderr_no_args" "usage:" "notion-page-api.sh stderr contains 'usage:' with no args"

# Fewer than 3 args
bash "$API_SCRIPT" "db-id" > /dev/null 2>&1; exit_one_arg=$?
assert_exit_nonzero "$exit_one_arg" "notion-page-api.sh exits non-zero with only 1 arg"

bash "$API_SCRIPT" "db-id" "title" > /dev/null 2>&1; exit_two_args=$?
assert_exit_nonzero "$exit_two_args" "notion-page-api.sh exits non-zero with only 2 args"

# Empty db_id — pass a fake token so the script reaches the empty-field check
NOTION_PERSONAL_TOKEN="ntn_fake" bash "$API_SCRIPT" "" "title" "desc" > /dev/null 2>&1; exit_empty_db=$?
assert_exit_nonzero "$exit_empty_db" "notion-page-api.sh exits non-zero when db_id is empty"

# No token (with valid args count) — use fake HOME to block secrets.env load
FAKE_HOME2=$(mktemp -d)
exit_no_token_api=0
stderr_no_token_api=$(HOME="$FAKE_HOME2" bash "$API_SCRIPT" "db-id" "title" "desc" 2>&1) || exit_no_token_api=$?
rm -rf "$FAKE_HOME2"
assert_exit_nonzero "$exit_no_token_api" "notion-page-api.sh exits non-zero when NOTION_PERSONAL_TOKEN not set"
assert_contains "$stderr_no_token_api" "NOTION_PERSONAL_TOKEN" "notion-page-api.sh stderr mentions NOTION_PERSONAL_TOKEN when missing"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
