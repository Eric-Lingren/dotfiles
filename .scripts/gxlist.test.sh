#!/usr/bin/env bash
# gxlist.test.sh — Unit tests for gxlist worktree inventory dashboard
# What: exercises default mode, --all, building detection, missing meta, empty inventory
# When: after changing gxlist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GXLIST="$SCRIPT_DIR/gxlist"

PASS=0
FAIL=0

ok()       { echo "  PASS: $1"; PASS=$((PASS + 1)); }
no()       { echo "  FAIL: $1"; echo "        expected: [$2]"; echo "        actual:   [$3]"; FAIL=$((FAIL + 1)); }
eq()       { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1" "$2" "$3"; fi; }
contains() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else no "$1" "contains: $3" "got: $2"; fi; }
lacks()    { if [[ "$2" != *"$3"* ]]; then ok "$1"; else no "$1" "must not contain: $3" "got: $2"; fi; }

# ─── Setup: source helper functions only ─────────────────────────────────────

GXLIST_SOURCED=true source "$GXLIST"

# ─── Temp dir setup ───────────────────────────────────────────────────────────

TMP=$(mktemp -d /tmp/gxlist-test-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Helper: write a .worktree-meta.json to a given path
write_meta() {
  local dir="$1"
  local ticket_id="$2"
  local linear_url="$3"
  local ticket_title="$4"
  local branch_name="$5"
  local status="$6"

  mkdir -p "$dir"
  python3 - "$dir/.worktree-meta.json" "$ticket_id" "$linear_url" "$ticket_title" "$branch_name" "$status" << 'PYEOF'
import json, sys
path, tid, url, title, branch, status = sys.argv[1:]
meta = {
    "linear_ticket_id": tid,
    "linear_url": url,
    "ticket_title": title,
    "branch_name": branch,
    "status": status,
    "picked_at": "2026-01-01T00:00:00Z",
}
with open(path, "w") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")
PYEOF
}

# ─── 1. gxlist_hyperlink ──────────────────────────────────────────────────────

echo "=== 1. gxlist_hyperlink ==="

result=$(gxlist_hyperlink "https://linear.app/issue/KEY-1" "KEY-1 title")
contains "OSC 8 open sequence" "$result" $'\033]8;'
contains "URL present" "$result" "https://linear.app/issue/KEY-1"
contains "text present" "$result" "KEY-1 title"
contains "OSC 8 close sequence" "$result" $'\033]8;;\033\\'

echo ""

# ─── 2. gxlist_is_building — mocked git ──────────────────────────────────────

echo "=== 2. gxlist_is_building ==="

# Mock git: return empty output (no commits ahead) for "none" paths,
# return one line for "some" paths
git() {
  # Called as: git -C <path> log origin/<base>..HEAD --oneline
  # $1=-C, $2=<path>, $3=log, $4=origin/base..HEAD, $5=--oneline
  local worktree_path="$2"
  if [[ "$worktree_path" == *"/no-commits"* ]]; then
    : # print nothing
  else
    echo "abc1234 Some commit"
  fi
}
export -f git

if gxlist_is_building "$TMP/some-commits" "main"; then
  ok "is_building=true when commits ahead"
else
  no "is_building=true when commits ahead" "true" "false"
fi

if ! gxlist_is_building "$TMP/no-commits" "main"; then
  ok "is_building=false when no commits"
else
  no "is_building=false when no commits" "false" "true"
fi

unset -f git
echo ""

# ─── 3. scan_repo_dir — basic operation ──────────────────────────────────────

echo "=== 3. scan_repo_dir ==="

SCAN_DIR="$TMP/scan-basic"
write_meta "$SCAN_DIR/feat-KEY-1-add-auth" \
  "KEY-1" "https://linear.app/issue/KEY-1" "Add auth" "feat/KEY-1-add-auth" "picked"

write_meta "$SCAN_DIR/feat-KEY-2-add-oauth" \
  "KEY-2" "https://linear.app/issue/KEY-2" "Add OAuth" "feat/KEY-2-add-oauth" "ready"

# Mock git to return no commits (so 'picked' stays 'picked')
git() { : ; }
export -f git

GX_BASE_BRANCH=main
output=$(scan_repo_dir "$SCAN_DIR")

contains "KEY-1 in output" "$output" "KEY-1"
contains "KEY-2 in output" "$output" "KEY-2"
contains "picked entry present" "$output" "picked"
contains "ready entry present" "$output" "ready"

unset -f git
echo ""

# ─── 4. Building detection override (picked → building) ───────────────────────

echo "=== 4. Building override: picked → building ==="

BUILD_DIR="$TMP/scan-building"
write_meta "$BUILD_DIR/feat-KEY-3-fix-login" \
  "KEY-3" "https://linear.app/issue/KEY-3" "Fix login" "feat/KEY-3-fix-login" "picked"

# Mock git: always returns one commit ahead
git() { echo "abc1234 Some commit"; }
export -f git

GX_BASE_BRANCH=main
output=$(scan_repo_dir "$BUILD_DIR")

contains "status upgraded to building" "$output" "building"
lacks "original picked status not shown" "$output" "picked"

unset -f git
echo ""

# ─── 5. Missing .worktree-meta.json → stderr warning + skip ──────────────────

echo "=== 5. Missing meta — warning on stderr ==="

MISS_DIR="$TMP/scan-missing"
mkdir -p "$MISS_DIR/no-meta-subdir"
# No .worktree-meta.json written

# Mock git to avoid real git calls
git() { : ; }
export -f git

stderr_output=$(scan_repo_dir "$MISS_DIR" 2>&1 >/dev/null)
stdout_output=$(scan_repo_dir "$MISS_DIR" 2>/dev/null)

contains "warning on stderr" "$stderr_output" "WARNING"
contains "warning mentions path" "$stderr_output" "no-meta-subdir"
eq "no stdout output for missing meta" "" "$stdout_output"

unset -f git
echo ""

# ─── 6. Malformed .worktree-meta.json → stderr warning + skip ────────────────

echo "=== 6. Malformed meta — warning on stderr ==="

MALFORM_DIR="$TMP/scan-malformed"
mkdir -p "$MALFORM_DIR/bad-meta-subdir"
echo '{not valid json}' > "$MALFORM_DIR/bad-meta-subdir/.worktree-meta.json"

MISSING_KEY_DIR="$TMP/scan-missing-key"
mkdir -p "$MISSING_KEY_DIR/missing-key-subdir"
echo '{"linear_ticket_id":"KEY-9"}' > "$MISSING_KEY_DIR/missing-key-subdir/.worktree-meta.json"

git() { : ; }
export -f git

stderr_bad=$(scan_repo_dir "$MALFORM_DIR" 2>&1 >/dev/null)
stdout_bad=$(scan_repo_dir "$MALFORM_DIR" 2>/dev/null)

contains "invalid JSON: warning on stderr" "$stderr_bad" "WARNING"
eq "invalid JSON: no stdout" "" "$stdout_bad"

stderr_missing=$(scan_repo_dir "$MISSING_KEY_DIR" 2>&1 >/dev/null)
stdout_missing=$(scan_repo_dir "$MISSING_KEY_DIR" 2>/dev/null)

contains "missing key: warning on stderr" "$stderr_missing" "WARNING"
eq "missing key: no stdout" "" "$stdout_missing"

unset -f git
echo ""

# ─── 7. Full script: default mode (current repo only) ────────────────────────

echo "=== 7. Default mode — current repo only ==="

BASE="$TMP/worktrees7"
REPO_A="my-repo"
REPO_B="other-repo"

write_meta "$BASE/$REPO_A/feat-KEY-10-do-thing" \
  "KEY-10" "https://linear.app/issue/KEY-10" "Do the thing" "feat/KEY-10-do-thing" "picked"

write_meta "$BASE/$REPO_B/feat-KEY-20-other-thing" \
  "KEY-20" "https://linear.app/issue/KEY-20" "Other thing" "feat/KEY-20-other-thing" "ready"

out=$(
  WORKTREE_BASE="$BASE" \
  GXLIST_CURRENT_REPO="$REPO_A" \
  GX_BASE_BRANCH=main \
  bash -c "
    git() { : ; }
    export -f git
    bash '$GXLIST'
  " 2>/dev/null
)

contains "default mode: shows current repo ticket" "$out" "Do the thing"
lacks "default mode: hides other repo ticket" "$out" "Other thing"
contains "default mode: PICKED section" "$out" "PICKED"

echo ""

# ─── 8. --all flag: shows worktrees across all repos ─────────────────────────

echo "=== 8. --all flag ==="

BASE8="$TMP/worktrees8"
write_meta "$BASE8/repo-a/feat-KEY-11-feat-one" \
  "KEY-11" "https://linear.app/issue/KEY-11" "Feature one" "feat/KEY-11-feat-one" "ready"
write_meta "$BASE8/repo-b/feat-KEY-12-feat-two" \
  "KEY-12" "https://linear.app/issue/KEY-12" "Feature two" "feat/KEY-12-feat-two" "picked"

out=$(
  WORKTREE_BASE="$BASE8" \
  GX_BASE_BRANCH=main \
  bash -c "
    git() { : ; }
    export -f git
    bash '$GXLIST' --all
  " 2>/dev/null
)

contains "--all: shows repo-a ticket" "$out" "Feature one"
contains "--all: shows repo-b ticket" "$out" "Feature two"
contains "--all: READY section" "$out" "READY"
contains "--all: PICKED section" "$out" "PICKED"

echo ""

# ─── 9. Empty inventory prints 'No active worktrees.' ─────────────────────────

echo "=== 9. Empty inventory ==="

BASE9="$TMP/worktrees9"
mkdir -p "$BASE9/empty-repo"
# No subdirs in empty-repo

out=$(
  WORKTREE_BASE="$BASE9" \
  GXLIST_CURRENT_REPO="empty-repo" \
  GX_BASE_BRANCH=main \
  bash -c "
    git() { : ; }
    export -f git
    bash '$GXLIST'
  " 2>/dev/null
)
rc=$?

eq "empty inventory: exit 0" "0" "$rc"
contains "empty inventory: message" "$out" "No active worktrees."

echo ""

# ─── 10. Linear URL is present in output ─────────────────────────────────────

echo "=== 10. Linear URL in output ==="

BASE10="$TMP/worktrees10"
write_meta "$BASE10/myrepo/feat-KEY-30-test-url" \
  "KEY-30" "https://linear.app/myorg/issue/KEY-30" "Test URL display" "feat/KEY-30-test-url" "ready"

out=$(
  WORKTREE_BASE="$BASE10" \
  GXLIST_CURRENT_REPO="myrepo" \
  GX_BASE_BRANCH=main \
  bash -c "
    git() { : ; }
    export -f git
    bash '$GXLIST'
  " 2>/dev/null
)

contains "linear URL in output" "$out" "https://linear.app/myorg/issue/KEY-30"

echo ""

# ─── 11. Building detection end-to-end: picked → building in output ───────────

echo "=== 11. Building override end-to-end ==="

BASE11="$TMP/worktrees11"
write_meta "$BASE11/myrepo/feat-KEY-40-should-build" \
  "KEY-40" "https://linear.app/issue/KEY-40" "Should show as building" "feat/KEY-40-should-build" "picked"

out=$(
  WORKTREE_BASE="$BASE11" \
  GXLIST_CURRENT_REPO="myrepo" \
  GX_BASE_BRANCH=main \
  bash -c "
    git() { echo 'abc1234 A commit ahead'; }
    export -f git
    bash '$GXLIST'
  " 2>/dev/null
)

contains "building override: in BUILDING section" "$out" "BUILDING"
contains "building override: ticket title present" "$out" "Should show as building"
lacks "building override: not in PICKED" "$out" "PICKED"

echo ""

# ─── Results ──────────────────────────────────────────────────────────────────

echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="
[[ "$FAIL" -eq 0 ]]
