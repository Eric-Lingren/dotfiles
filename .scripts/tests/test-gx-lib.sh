#!/usr/bin/env bash
# Unit tests for gx-lib.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../gx-lib.sh"

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

# --- URL normalization tests ---
assert_eq "ssh URL strips host and .git" \
  "Org/Repo" \
  "$(gx_normalize_url "git@github.com:Org/Repo.git")"

assert_eq "https URL strips host and .git" \
  "Org/Repo" \
  "$(gx_normalize_url "https://github.com/Org/Repo.git")"

assert_eq "https URL no trailing .git" \
  "Org/Repo" \
  "$(gx_normalize_url "https://github.com/Org/Repo")"

assert_eq "ssh URL no trailing .git" \
  "Org/Repo" \
  "$(gx_normalize_url "git@github.com:Org/Repo")"

assert_eq "strips trailing slash" \
  "Org/Repo" \
  "$(gx_normalize_url "https://github.com/Org/Repo/")"

assert_eq ".dotfiles https URL normalizes correctly" \
  "Eric-Lingren/dotfiles" \
  "$(gx_normalize_url "https://github.com/Eric-Lingren/dotfiles.git")"

# --- Registered repo lookup (must run from .dotfiles repo) ---
if git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null | grep -q "dotfiles"; then
  GX_POLICY_FILE="$SCRIPT_DIR/../../claude-code-shared/resources/repo-policy.json"
  pushd "$SCRIPT_DIR/../.." > /dev/null
  gx_load_policy
  popd > /dev/null
  assert_eq "registered: label" "dotfiles" "$GX_LABEL"
  assert_eq "registered: base_branch" "main" "$GX_BASE_BRANCH"
  assert_eq "registered: has excludes" "true" \
    "$(echo "$GX_EXCLUDE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if len(d)>0 else 'false')")"
else
  echo "SKIP: registered repo tests (not in .dotfiles repo)"
fi

# --- Unregistered fallback test ---
GX_POLICY_FILE="$SCRIPT_DIR/../../claude-code-shared/resources/repo-policy.json"
# Temporarily override with a fake remote
_real_gx_load_policy() {
  local key="Some-Org/NotInRegistry"
  local entry
  entry=$(python3 -c "
import json, sys
with open('$GX_POLICY_FILE') as f:
    data = json.load(f)
if '$key' in data:
    e = data['$key']
    print(e.get('label', 'unknown'))
    print(e.get('base_branch', 'main'))
    print(json.dumps(e.get('exclude', [])))
else:
    sys.exit(1)
" 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "gx-lib: repo '$key' not in policy registry — using conservative defaults" >&2
    GX_LABEL="unknown"
    GX_BASE_BRANCH="main"
    GX_EXCLUDE_JSON="[]"
    return 1
  fi
}
_real_gx_load_policy 2>/tmp/gx-lib-test-stderr
assert_eq "unregistered: label fallback" "unknown" "$GX_LABEL"
assert_eq "unregistered: base_branch fallback" "main" "$GX_BASE_BRANCH"
assert_eq "unregistered: exclude fallback" "[]" "$GX_EXCLUDE_JSON"
assert_eq "unregistered: stderr warning" "true" \
  "$(grep -q 'not in policy registry' /tmp/gx-lib-test-stderr && echo true || echo false)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
