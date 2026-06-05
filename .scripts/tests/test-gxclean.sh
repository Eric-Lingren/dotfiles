#!/usr/bin/env bash
# Unit tests for gxclean

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GXCLEAN="$SCRIPT_DIR/../gxclean"

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
    echo "  in: $(echo "$haystack" | head -10)"
    ((FAIL++))
  fi
}

# Test: executable
if [[ -x "$GXCLEAN" ]]; then
  echo "PASS: gxclean is executable"
  ((PASS++))
else
  echo "FAIL: gxclean is not executable"
  ((FAIL++))
fi

# Test: output with N input — does not delete anything
OUTPUT=$(echo "N" | "$GXCLEAN" 2>/dev/null)
EXIT_CODE=$?
assert_eq "gxclean exits 0" "0" "$EXIT_CODE"

# Test: output mentions Aborted or No merged branches (either is valid)
if echo "$OUTPUT" | grep -qE "Aborted|No merged branches"; then
  echo "PASS: confirms N aborts"
  ((PASS++))
else
  echo "FAIL: did not abort or report no branches"
  echo "  actual: $OUTPUT"
  ((FAIL++))
fi

# Test: if merged branches exist, they are listed before prompt
MERGED_LIST=$(git branch --merged origin/main 2>/dev/null | grep -v "^\*" | grep -v "^\s*main\s*$" | sed 's/^[[:space:]]*//' | grep -v "^$")
if [[ -n "$MERGED_LIST" ]]; then
  assert_contains "merged branches listed in output" "MERGED BRANCHES" "$OUTPUT"
fi

# Test: prototype/* branches get [PRIORITY] flag
if echo "$MERGED_LIST" | grep -q "prototype/"; then
  assert_contains "prototype branches flagged [PRIORITY]" "PRIORITY" "$OUTPUT"
fi

# Test: ON_BASE warning appears when on base branch
BASE="${GX_BASE_BRANCH:-main}"
CURRENT=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT" == "$BASE" ]]; then
  assert_contains "ON_BASE warning when on base" "currently on base branch" "$OUTPUT"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
