#!/usr/bin/env bash
# Unit tests for gxpush

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GXPUSH="$SCRIPT_DIR/../gxpush"

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
    echo "  in output (first 5 lines): $(echo "$haystack" | head -5)"
    ((FAIL++))
  fi
}

# Test: script is executable
if [[ -x "$GXPUSH" ]]; then
  echo "PASS: gxpush is executable"
  ((PASS++))
else
  echo "FAIL: gxpush is not executable"
  ((FAIL++))
fi

# Test: preview contains all required sections
# Run with N input (abort) to test preview only
OUTPUT=$(echo "N" | "$GXPUSH" 2>/dev/null)
assert_contains "preview has STAGED section" "STAGED" "$OUTPUT"
assert_contains "preview has WILL ADD section" "WILL ADD" "$OUTPUT"
assert_contains "preview has EXCLUDED section" "EXCLUDED" "$OUTPUT"
assert_contains "preview has SECRETS section" "SECRETS" "$OUTPUT"

# Test: default is N (abort without 'y')
RESULT=$(echo "" | "$GXPUSH" 2>/dev/null)
if echo "$RESULT" | grep -qE "Aborted|Nothing to commit"; then
  echo "PASS: empty input aborts (default N)"
  ((PASS++))
else
  echo "FAIL: empty input did not abort"
  echo "  actual: $RESULT"
  ((FAIL++))
fi

# Test: branch name in preview
BRANCH=$(git rev-parse --abbrev-ref HEAD)
PREVIEW=$(echo "N" | "$GXPUSH" 2>/dev/null)
assert_contains "preview shows branch name" "$BRANCH" "$PREVIEW"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
