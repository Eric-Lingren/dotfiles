#!/usr/bin/env bash
# Unit tests for gxsync

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GXSYNC="$SCRIPT_DIR/../gxsync"

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
if [[ -x "$GXSYNC" ]]; then
  echo "PASS: gxsync is executable"
  ((PASS++))
else
  echo "FAIL: gxsync is not executable"
  ((FAIL++))
fi

# Test: preview shows ahead/behind counts and merge intent
# Using N to abort after preview
OUTPUT=$(echo "N" | "$GXSYNC" 2>/dev/null)
EXIT_CODE=$?
assert_eq "gxsync exits 0 on N" "0" "$EXIT_CODE"

# Either it aborts (feature branch) or exits with "up to date" / "already on base"
if echo "$OUTPUT" | grep -qE "Aborted|up to date|already on base branch"; then
  echo "PASS: gxsync aborts or exits cleanly"
  ((PASS++))
else
  echo "FAIL: unexpected output"
  echo "  actual: $OUTPUT"
  ((FAIL++))
fi

# Test: preview shows ahead/behind when on a feature branch
CURRENT=$(git rev-parse --abbrev-ref HEAD)
BASE="${GX_BASE_BRANCH:-main}"
if [[ "$CURRENT" != "$BASE" ]]; then
  assert_contains "preview shows ahead count" "ahead" "$OUTPUT"
  assert_contains "preview shows behind count" "behind" "$OUTPUT"
  assert_contains "preview shows merge intent" "Will merge" "$OUTPUT"
fi

# Test: script contains no 'rebase' or 'force' invocations
if grep -qE '\brebase\b|push.*-f\b|push.*--force\b' "$GXSYNC"; then
  echo "FAIL: gxsync contains rebase or force-push"
  ((FAIL++))
else
  echo "PASS: gxsync has no rebase or force-push"
  ((PASS++))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
