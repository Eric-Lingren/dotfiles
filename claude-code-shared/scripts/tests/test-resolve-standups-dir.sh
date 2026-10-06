#!/usr/bin/env bash
# Tests for resolve-standups-dir.sh
# Uses temporary git repos as fixtures — no real remote calls are made.
#
# Usage: bash test-resolve-standups-dir.sh
# Exit 0 = all tests passed. Exit 1 = one or more failed.

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPTS_DIR/standup/resolve-standups-dir.sh"

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local actual="$1" expected="$2" desc="$3"
  if [ "$actual" = "$expected" ]; then
    assert_pass "$desc"
  else
    assert_fail "$desc (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local text="$1" pattern="$2" desc="$3"
  if echo "$text" | grep -q "$pattern"; then
    assert_pass "$desc"
  else
    assert_fail "$desc (pattern '$pattern' not found in: $text)"
  fi
}

assert_exit_zero() {
  local code="$1" desc="$2"
  if [ "$code" -eq 0 ]; then
    assert_pass "$desc"
  else
    assert_fail "$desc (exited $code, expected 0)"
  fi
}

# --- Test 1: script exists and is executable ---
echo "=== T1: script exists ==="
if [ -f "$SCRIPT" ]; then
  assert_pass "resolve-standups-dir.sh exists"
else
  assert_fail "resolve-standups-dir.sh not found at $SCRIPT"
fi
if [ -x "$SCRIPT" ]; then
  assert_pass "resolve-standups-dir.sh is executable"
else
  assert_fail "resolve-standups-dir.sh is not executable"
fi

# --- Helper: create a temp git repo with an origin remote ---
make_git_repo() {
  local dir="$1"
  local remote_url="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  # Create initial commit so HEAD exists
  touch "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "init"
  git -C "$dir" remote add origin "$remote_url"
}

# --- Test 2: QUAESTOR_WEB_DIR env var resolution ---
echo ""
echo "=== T2: QUAESTOR_WEB_DIR env var ==="
QW_DIR="$TMP/quaestor-web"
mkdir -p "$QW_DIR"
set +e
RESOLVED=$(cd "$TMP" && QUAESTOR_WEB_DIR="$QW_DIR" bash "$SCRIPT" 2>"$TMP/t2.err")
EXIT2=$?
set -e
assert_exit_zero "$EXIT2" "exits 0 with QUAESTOR_WEB_DIR set"
assert_eq "$RESOLVED" "$QW_DIR/docs/standups" "resolves to \$QUAESTOR_WEB_DIR/docs/standups"

# --- Test 3: origin remote matching Quaestor-Technologies/Quaestor-Web ---
echo ""
echo "=== T3: origin remote match ==="
QW_REPO="$TMP/qw-repo"
make_git_repo "$QW_REPO" "https://github.com/Quaestor-Technologies/Quaestor-Web.git"
set +e
RESOLVED3=$(cd "$QW_REPO" && unset QUAESTOR_WEB_DIR 2>/dev/null; QUAESTOR_WEB_DIR="" bash "$SCRIPT" 2>"$TMP/t3.err")
EXIT3=$?
set -e
assert_exit_zero "$EXIT3" "exits 0 from Quaestor-Web repo"
assert_contains "$RESOLVED3" "docs/standups" "resolved path ends with docs/standups"
assert_contains "$RESOLVED3" "$QW_REPO" "resolved path includes repo root"

# --- Test 4: non-matching repo with no QUAESTOR_WEB_DIR → exit 1 ---
echo ""
echo "=== T4: no match → exit 1 with hint ==="
OTHER_REPO="$TMP/other-repo"
make_git_repo "$OTHER_REPO" "https://github.com/owner/other-repo.git"
set +e
OUT4=$(cd "$OTHER_REPO" && QUAESTOR_WEB_DIR="" bash "$SCRIPT" 2>"$TMP/t4.err")
EXIT4=$?
set -e
if [ "$EXIT4" -ne 0 ]; then
  assert_pass "exits non-zero when no match and no QUAESTOR_WEB_DIR"
else
  assert_fail "should exit non-zero when no match"
fi
if grep -q "QUAESTOR_WEB_DIR" "$TMP/t4.err" 2>/dev/null; then
  assert_pass "stderr contains QUAESTOR_WEB_DIR hint"
else
  assert_fail "stderr should mention QUAESTOR_WEB_DIR. Got: $(cat "$TMP/t4.err")"
fi

# --- Test 5: --ensure creates docs/standups/ directory ---
echo ""
echo "=== T5: --ensure creates dir ==="
QW_ENSURE="$TMP/qw-ensure"
mkdir -p "$QW_ENSURE"
set +e
RESOLVED5=$(cd "$TMP" && QUAESTOR_WEB_DIR="$QW_ENSURE" bash "$SCRIPT" --ensure 2>"$TMP/t5.err")
EXIT5=$?
set -e
assert_exit_zero "$EXIT5" "--ensure exits 0"
if [ -d "$QW_ENSURE/docs/standups" ]; then
  assert_pass "--ensure created docs/standups/ directory"
else
  assert_fail "--ensure did not create docs/standups/ at $QW_ENSURE/docs/standups"
fi

# --- Test 6: --ensure adds docs/standups/ to git exclude (idempotent) ---
echo ""
echo "=== T6: --ensure updates git exclude idempotently ==="
QW_EXCL_REPO="$TMP/qw-excl-repo"
make_git_repo "$QW_EXCL_REPO" "https://github.com/Quaestor-Technologies/Quaestor-Web.git"
mkdir -p "$QW_EXCL_REPO/.git/info"

# Run --ensure once
set +e
RESOLVED6a=$(cd "$QW_EXCL_REPO" && QUAESTOR_WEB_DIR="" bash "$SCRIPT" --ensure 2>"$TMP/t6a.err")
EXIT6a=$?
set -e
assert_exit_zero "$EXIT6a" "--ensure first run exits 0"

EXCLUDE_FILE="$QW_EXCL_REPO/.git/info/exclude"
if grep -qxF "docs/standups/" "$EXCLUDE_FILE" 2>/dev/null; then
  assert_pass "docs/standups/ added to .git/info/exclude"
else
  assert_fail "docs/standups/ not found in .git/info/exclude. Content: $(cat "$EXCLUDE_FILE" 2>/dev/null || echo '(missing)')"
fi

# Run --ensure again (idempotent)
set +e
RESOLVED6b=$(cd "$QW_EXCL_REPO" && QUAESTOR_WEB_DIR="" bash "$SCRIPT" --ensure 2>"$TMP/t6b.err")
EXIT6b=$?
set -e
assert_exit_zero "$EXIT6b" "--ensure second run exits 0"

EXCL_COUNT=$(grep -cxF "docs/standups/" "$EXCLUDE_FILE" 2>/dev/null || echo "0")
assert_eq "$EXCL_COUNT" "1" "docs/standups/ appears exactly once in exclude (idempotent)"

# --- Test 7: --ensure does NOT touch .gitignore ---
echo ""
echo "=== T7: --ensure does not touch .gitignore ==="
QW_GITIGN="$TMP/qw-gitign"
make_git_repo "$QW_GITIGN" "https://github.com/Quaestor-Technologies/Quaestor-Web.git"
GITIGNORE="$QW_GITIGN/.gitignore"
echo "*.log" > "$GITIGNORE"
BEFORE=$(cat "$GITIGNORE")

set +e
cd "$QW_GITIGN" && QUAESTOR_WEB_DIR="" bash "$SCRIPT" --ensure >/dev/null 2>&1
set -e

AFTER=$(cat "$GITIGNORE")
if [ "$BEFORE" = "$AFTER" ]; then
  assert_pass ".gitignore not modified by --ensure"
else
  assert_fail ".gitignore was modified. Before: $BEFORE | After: $AFTER"
fi

if ! grep -q "standups" "$GITIGNORE" 2>/dev/null; then
  assert_pass ".gitignore does not contain standups entry"
else
  assert_fail ".gitignore should not contain standups. Got: $(cat "$GITIGNORE")"
fi

# --- Results ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
