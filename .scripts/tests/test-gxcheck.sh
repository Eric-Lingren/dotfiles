#!/usr/bin/env bash
# Unit tests for gxcheck

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GXCHECK="$SCRIPT_DIR/../gxcheck"

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
    echo "  in:          $haystack"
    ((FAIL++))
  fi
}

# Test: script is executable
if [[ -x "$GXCHECK" ]]; then
  echo "PASS: gxcheck is executable"
  ((PASS++))
else
  echo "FAIL: gxcheck is not executable"
  ((FAIL++))
fi

# Test: exit code is always 0 (regardless of warnings)
"$GXCHECK" > /dev/null 2>&1
EXIT_CODE=$?
assert_eq "gxcheck always exits 0" "0" "$EXIT_CODE"

# Test: produces output (either OK or WARNs)
OUTPUT=$("$GXCHECK" 2>/dev/null)
if [[ -n "$OUTPUT" ]]; then
  echo "PASS: gxcheck produces output"
  ((PASS++))
else
  echo "FAIL: gxcheck produced no output"
  ((FAIL++))
fi

# Test: output matches expected patterns (OK or WARN lines)
if echo "$OUTPUT" | grep -qE '^(OK:|WARN:)'; then
  echo "PASS: output uses OK:/WARN: prefixes"
  ((PASS++))
else
  echo "FAIL: output does not use OK:/WARN: prefixes"
  echo "  actual: $OUTPUT"
  ((FAIL++))
fi

# Test: ON_BASE signal — inject base branch == current branch via env
CURRENT=$(git rev-parse --abbrev-ref HEAD)
ON_BASE_OUTPUT=$(GX_BASE_BRANCH="$CURRENT" "$GXCHECK" 2>/dev/null)
if echo "$ON_BASE_OUTPUT" | grep -q "currently on base branch"; then
  echo "PASS: ON_BASE signal fires when on base branch"
  ((PASS++))
else
  echo "FAIL: ON_BASE signal missing"
  ((FAIL++))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
