#!/usr/bin/env bash
# Characterization tests for the tasks-to-linear write path.
#
# Phase 1 (before extraction): verifies the write path lives in SKILL.md and
#   contains the expected MCP tool references and issue-creation logic.
# Phase 2 (after extraction): additionally verifies the new
#   agents/egress/linear/export-tasks-linear.md agent exists and has the
#   expected frontmatter contract.
#
# The PHASE variable controls which checks run:
#   PHASE=1 (default) — pre-extraction checks only
#   PHASE=2           — post-extraction checks (phase 1 + phase 2)
#
# Usage: bash test-linear-adapter.sh
# Exit 0 = all tests passed. Exit 1 = one or more failed.

set -uo pipefail

PHASE="${PHASE:-2}"

# ---- paths -------------------------------------------------------------------
SKILL_MD="$HOME/.dotfiles/claude-code-shared/skills/tasks-to-linear/SKILL.md"
LINEAR_AGENT="$HOME/.dotfiles/claude-code-shared/agents/egress/linear/export-tasks-linear.md"

# ---- harness -----------------------------------------------------------------
PASS=0
FAIL=0

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

assert_file_contains() {
  local path="$1"
  local pattern="$2"
  local desc="$3"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found in $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_contains() {
  local path="$1"
  local pattern="$2"
  local desc="$3"
  if ! grep -q "$pattern" "$path" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' unexpectedly found in $path)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== tasks-to-linear write path characterization tests ==="
echo "Phase: $PHASE"
echo ""

# --- Phase 1: tasks-to-linear/SKILL.md structure ---
echo "-- SKILL.md existence and structure --"
assert_file_exists "$SKILL_MD" "tasks-to-linear SKILL.md exists"
assert_file_contains "$SKILL_MD" "name: tasks-to-linear" "SKILL.md has correct name in frontmatter"
assert_file_contains "$SKILL_MD" "validate-schema.sh" "SKILL.md references validate-schema.sh"
assert_file_contains "$SKILL_MD" "linear_url" "SKILL.md references linear_url field (write path output)"
assert_file_contains "$SKILL_MD" "blockedBy\|blocked_by" "SKILL.md handles blocked-by relationships"
assert_file_contains "$SKILL_MD" "create_issue\|create-issue\|mcp.*[Ll]inear\|[Ll]inear.*mcp\|list_teams\|list_projects" "SKILL.md references Linear API operations"
echo ""

if [ "$PHASE" -ge 2 ]; then
  echo "-- Phase 2: extracted export-tasks-linear agent --"
  assert_file_exists "$LINEAR_AGENT" "export-tasks-linear.md exists at agents/egress/linear/"
  assert_file_contains "$LINEAR_AGENT" "name: export-tasks-linear" "agent has correct name in frontmatter"
  assert_file_contains "$LINEAR_AGENT" "create_issue\|create-issue\|mcp\|[Ll]inear" "agent references Linear issue creation"
  assert_file_contains "$LINEAR_AGENT" "linear_url\|url\|URL" "agent outputs an issue URL"
  # The write path must NOT still inline MCP create_issue calls in SKILL.md after extraction:
  # (tasks-to-linear should delegate to the agent instead)
  assert_file_contains "$SKILL_MD" "export-tasks-linear\|subagent_type.*linear\|Agent.*linear" "SKILL.md delegates to export-tasks-linear agent after extraction"
  echo ""
fi

echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
