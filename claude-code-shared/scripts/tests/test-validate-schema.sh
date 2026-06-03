#!/usr/bin/env bash
# Deterministic fixtures test for validate-schema.sh against task-schema.json.
# Four cases: valid, missing-required-field, wrong-schema_version, extra-undeclared-field.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACTS_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)/contracts"
VALIDATOR="$SCRIPTS_DIR/validate-schema.sh"
SCHEMA="$CONTRACTS_DIR/task-schema.json"
TMP=$(mktemp -d)

PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

assert_pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

run_case() {
  local name="$1"
  local file="$2"
  local expect_exit="$3"

  set +e
  "$VALIDATOR" "$SCHEMA" "$file" 2>/tmp/validate-stderr
  local actual_exit=$?
  set -e

  if [ "$expect_exit" -eq 0 ] && [ "$actual_exit" -eq 0 ]; then
    assert_pass "$name: exited 0 (valid)"
  elif [ "$expect_exit" -ne 0 ] && [ "$actual_exit" -ne 0 ]; then
    assert_pass "$name: exited non-zero (invalid, correctly rejected)"
  elif [ "$expect_exit" -eq 0 ] && [ "$actual_exit" -ne 0 ]; then
    assert_fail "$name: expected exit 0 but got $actual_exit. stderr: $(cat /tmp/validate-stderr)"
  else
    assert_fail "$name: expected non-zero but exited 0 (should have been rejected)"
  fi
}

echo "=== validate-schema.sh fixtures test ==="

# Fixture 1: valid minimal task file
VALID="$TMP/valid-task.json"
cat > "$VALID" <<'EOF'
{
  "schema_version": "1",
  "prd": "docs/prd/20260101-1200-my-feature.md",
  "generated_at": "2026-01-01T12:00:00Z",
  "branching": { "strategy": "single", "branch": "feat/my-feature" },
  "tasks": [
    {
      "id": "T-0001",
      "title": "Do the thing",
      "type": "AFK",
      "description": "End-to-end description of the task.",
      "acceptance_criteria": ["Tests pass"],
      "blocked_by": [],
      "status": "not_started",
      "branch": "feat/my-feature",
      "pr": null
    }
  ],
  "follow_ups": []
}
EOF
run_case "Fixture 1 (valid)" "$VALID" 0

# Fixture 2: missing required field (no 'title' on task)
MISSING="$TMP/missing-field.json"
cat > "$MISSING" <<'EOF'
{
  "schema_version": "1",
  "prd": null,
  "generated_at": "2026-01-01T12:00:00Z",
  "branching": { "strategy": "single" },
  "tasks": [
    {
      "id": "T-0001",
      "type": "AFK",
      "description": "No title field.",
      "acceptance_criteria": ["Tests pass"],
      "blocked_by": [],
      "status": "not_started",
      "branch": null,
      "pr": null
    }
  ],
  "follow_ups": []
}
EOF
run_case "Fixture 2 (missing required field: title)" "$MISSING" 1

# Fixture 3: wrong schema_version
WRONG_VER="$TMP/wrong-version.json"
cat > "$WRONG_VER" <<'EOF'
{
  "schema_version": "99",
  "prd": null,
  "generated_at": "2026-01-01T12:00:00Z",
  "branching": { "strategy": "single" },
  "tasks": [],
  "follow_ups": []
}
EOF
run_case "Fixture 3 (wrong schema_version '99')" "$WRONG_VER" 1

# Fixture 4: extra undeclared field at top level
EXTRA="$TMP/extra-field.json"
cat > "$EXTRA" <<'EOF'
{
  "schema_version": "1",
  "prd": null,
  "generated_at": "2026-01-01T12:00:00Z",
  "branching": { "strategy": "single" },
  "tasks": [],
  "follow_ups": [],
  "undeclared_field": "should be rejected"
}
EOF
run_case "Fixture 4 (extra undeclared field)" "$EXTRA" 1

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
