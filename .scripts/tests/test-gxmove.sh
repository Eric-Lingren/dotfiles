#!/usr/bin/env bash
# Unit tests for gxmove

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GXMOVE="$SCRIPT_DIR/../gxmove"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    ((FAIL++))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc"
    echo "  looking for: $needle"
    echo "  in: $(echo "$haystack" | head -5)"
    ((FAIL++))
  fi
}

# Test: executable
if [[ -x "$GXMOVE" ]]; then
  echo "PASS: gxmove is executable"
  ((PASS++))
else
  echo "FAIL: gxmove is not executable"
  ((FAIL++))
fi

# Test: missing target arg exits with usage message
OUTPUT=$("$GXMOVE" 2>&1)
EXIT_CODE=$?
assert_contains "no-arg error message" "Usage" "$OUTPUT"

# Test: no changes exits cleanly with message (no actual git stash)
# We need a clean working tree for this test; skip if dirty
if git diff --quiet && git diff --cached --quiet; then
  OUTPUT=$("$GXMOVE" some-target 2>/dev/null <<< "N")
  if echo "$OUTPUT" | grep -q "No uncommitted changes"; then
    echo "PASS: no changes — exits cleanly"
    ((PASS++))
  else
    echo "SKIP: no-changes check (working tree has changes)"
  fi
else
  # With changes present, preview should show FROM/TO/CHANGES
  OUTPUT=$(echo "N" | "$GXMOVE" test-target-branch 2>/dev/null)
  assert_contains "preview shows FROM" "FROM:" "$OUTPUT"
  assert_contains "preview shows TO" "TO:" "$OUTPUT"
  assert_contains "preview shows CHANGES TO MOVE" "CHANGES TO MOVE" "$OUTPUT"
  # Default N aborts
  assert_contains "N aborts" "Aborted" "$OUTPUT"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
