#!/usr/bin/env bash
# gxship.test.sh — Unit tests for gxship worktree shipping
# What: exercises meta-file detection, prompt routing, status transitions, rebase conflict handling
# When: after changing gxship

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GXSHIP="$SCRIPT_DIR/gxship"

PASS=0
FAIL=0

ok()       { echo "  PASS: $1"; PASS=$((PASS + 1)); }
no()       { echo "  FAIL: $1"; echo "        expected: [$2]"; echo "        actual:   [$3]"; FAIL=$((FAIL + 1)); }
eq()       { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1" "$2" "$3"; fi; }
contains() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else no "$1" "contains: $3" "got: $2"; fi; }
lacks()    { if [[ "$2" != *"$3"* ]]; then ok "$1"; else no "$1" "must not contain: $3" "got: $2"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ─── Fixtures ────────────────────────────────────────────────────────────────

make_meta() {
  local dir="$1"
  local status="$2"
  python3 -c "
import json
meta = {
    'linear_ticket_id': 'KEY-123',
    'linear_url': 'https://linear.app/org/issue/KEY-123',
    'ticket_title': 'Test Ticket',
    'branch_name': 'feat/KEY-123-test-ticket',
    'status': '$status',
    'picked_at': '2026-01-01T00:00:00Z',
}
with open('$dir/.worktree-meta.json', 'w') as f:
    json.dump(meta, f, indent=2)
    f.write('\n')
"
}

get_meta_status() {
  local dir="$1"
  python3 -c "import json; d=json.load(open('$dir/.worktree-meta.json')); print(d.get('status',''))"
}

# ─── Mock helpers ────────────────────────────────────────────────────────────

# Create a mock git binary. Pass MOCK_GIT_REBASE_EXIT to control rebase exit code.
make_mock_git() {
  local bin_dir="$1"
  local rebase_exit="${2:-0}"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/git" << GITEOF
#!/usr/bin/env bash
cmd="\$1"
case "\$cmd" in
  remote)  exit 1 ;;
  fetch)   exit 0 ;;
  rebase)
    if [[ "\$2" == "--abort" ]]; then exit 0; fi
    exit $rebase_exit
    ;;
  *)       exit 0 ;;
esac
GITEOF
  chmod +x "$bin_dir/git"
}

# Create a mock gxpush that logs calls to a file
make_mock_gxpush() {
  local path="$1"
  local log_file="$2"
  cat > "$path" << PUSHEOF
#!/usr/bin/env bash
echo "\$@" >> "$log_file"
PUSHEOF
  chmod +x "$path"
}

# Run gxship in a subprocess with full mocking
# Args: test_dir (contains .worktree-meta.json), bin_dir (mock git), gxpush_path, input, extra_env
run_gxship() {
  local test_dir="$1"
  local bin_dir="$2"
  local gxpush_path="$3"
  local input="$4"
  shift 4
  local extra_env=("$@")

  env GX_BASE_BRANCH=main \
      GXPUSH="$gxpush_path" \
      PATH="$bin_dir:$PATH" \
      "${extra_env[@]+"${extra_env[@]}"}" \
      bash "$GXSHIP" <<< "$input" 2>&1
}

# ─── 1. Missing .worktree-meta.json ──────────────────────────────────────────

echo "=== 1. Missing .worktree-meta.json ==="

T1="$TMP/t1"
mkdir -p "$T1"
MOCK_BIN1="$TMP/bin1"
make_mock_git "$MOCK_BIN1" 0
MOCK_PUSH1="$TMP/gxpush1"
PUSH_LOG1="$TMP/push1.log"
make_mock_gxpush "$MOCK_PUSH1" "$PUSH_LOG1"

out=$(cd "$T1" && env GX_BASE_BRANCH=main GXPUSH="$MOCK_PUSH1" PATH="$MOCK_BIN1:$PATH" bash "$GXSHIP" <<< "Y" 2>&1) && rc=$? || rc=$?
eq "missing meta: exit 1" "1" "$rc"
contains "missing meta: error message" "$out" "worktree-meta.json"
lacks "missing meta: gxpush not called" "$(cat "$PUSH_LOG1" 2>/dev/null)" "--auto"

echo ""

# ─── 2. building → ship (Y) ───────────────────────────────────────────────

echo "=== 2. building → ship (Y) ==="

T2="$TMP/t2"
mkdir -p "$T2"
make_meta "$T2" "building"
MOCK_BIN2="$TMP/bin2"
make_mock_git "$MOCK_BIN2" 0
MOCK_PUSH2="$TMP/gxpush2"
PUSH_LOG2="$TMP/push2.log"
make_mock_gxpush "$MOCK_PUSH2" "$PUSH_LOG2"

out=$(cd "$T2" && env GX_BASE_BRANCH=main GXPUSH="$MOCK_PUSH2" PATH="$MOCK_BIN2:$PATH" bash "$GXSHIP" <<< "Y" 2>&1) && rc=$? || rc=$?
eq "building→ship Y: exit 0" "0" "$rc"
eq "building→ship Y: status=shipped" "shipped" "$(get_meta_status "$T2")"
contains "building→ship Y: gxpush called" "$(cat "$PUSH_LOG2" 2>/dev/null)" "--auto"
contains "building→ship Y: gxpush --pr flag" "$(cat "$PUSH_LOG2" 2>/dev/null)" "--pr"
contains "building→ship Y: descriptive message" "$out" "Will rebase onto"
contains "building→ship Y: building prompt includes [r]" "$out" "[r]"

echo ""

# ─── 3. building → ship (Enter / empty) ──────────────────────────────────────

echo "=== 3. building → ship (Enter) ==="

T3="$TMP/t3"
mkdir -p "$T3"
make_meta "$T3" "building"
MOCK_BIN3="$TMP/bin3"
make_mock_git "$MOCK_BIN3" 0
MOCK_PUSH3="$TMP/gxpush3"
PUSH_LOG3="$TMP/push3.log"
make_mock_gxpush "$MOCK_PUSH3" "$PUSH_LOG3"

out=$(cd "$T3" && env GX_BASE_BRANCH=main GXPUSH="$MOCK_PUSH3" PATH="$MOCK_BIN3:$PATH" bash "$GXSHIP" <<< "" 2>&1) && rc=$? || rc=$?
eq "building→ship Enter: exit 0" "0" "$rc"
eq "building→ship Enter: status=shipped" "shipped" "$(get_meta_status "$T3")"
contains "building→ship Enter: gxpush called" "$(cat "$PUSH_LOG3" 2>/dev/null)" "--auto"

echo ""

# ─── 4. building → ready (r) ─────────────────────────────────────────────────

echo "=== 4. building → ready (r) ==="

T4="$TMP/t4"
mkdir -p "$T4"
make_meta "$T4" "building"
MOCK_BIN4="$TMP/bin4"
make_mock_git "$MOCK_BIN4" 0
MOCK_PUSH4="$TMP/gxpush4"
PUSH_LOG4="$TMP/push4.log"
make_mock_gxpush "$MOCK_PUSH4" "$PUSH_LOG4"

out=$(cd "$T4" && env GX_BASE_BRANCH=main GXPUSH="$MOCK_PUSH4" PATH="$MOCK_BIN4:$PATH" bash "$GXSHIP" <<< "r" 2>&1) && rc=$? || rc=$?
eq "building→ready r: exit 0" "0" "$rc"
eq "building→ready r: status=ready" "ready" "$(get_meta_status "$T4")"
lacks "building→ready r: gxpush NOT called" "$(cat "$PUSH_LOG4" 2>/dev/null)" "--auto"
contains "building→ready r: message" "$out" "Marked as ready"

echo ""

# ─── 5. ready → ship (Y) ─────────────────────────────────────────────────────

echo "=== 5. ready → ship (Y) ==="

T5="$TMP/t5"
mkdir -p "$T5"
make_meta "$T5" "ready"
MOCK_BIN5="$TMP/bin5"
make_mock_git "$MOCK_BIN5" 0
MOCK_PUSH5="$TMP/gxpush5"
PUSH_LOG5="$TMP/push5.log"
make_mock_gxpush "$MOCK_PUSH5" "$PUSH_LOG5"

out=$(cd "$T5" && env GX_BASE_BRANCH=main GXPUSH="$MOCK_PUSH5" PATH="$MOCK_BIN5:$PATH" bash "$GXSHIP" <<< "Y" 2>&1) && rc=$? || rc=$?
eq "ready→ship Y: exit 0" "0" "$rc"
eq "ready→ship Y: status=shipped" "shipped" "$(get_meta_status "$T5")"
contains "ready→ship Y: gxpush called" "$(cat "$PUSH_LOG5" 2>/dev/null)" "--auto"
# Ready-state prompt must NOT include [r]
lacks "ready prompt: no [r] option" "$out" "Ready but later"

echo ""

# ─── 6. abort (n) ────────────────────────────────────────────────────────────

echo "=== 6. abort (n) ==="

T6="$TMP/t6"
mkdir -p "$T6"
make_meta "$T6" "building"
MOCK_BIN6="$TMP/bin6"
make_mock_git "$MOCK_BIN6" 0
MOCK_PUSH6="$TMP/gxpush6"
PUSH_LOG6="$TMP/push6.log"
make_mock_gxpush "$MOCK_PUSH6" "$PUSH_LOG6"

out=$(cd "$T6" && env GX_BASE_BRANCH=main GXPUSH="$MOCK_PUSH6" PATH="$MOCK_BIN6:$PATH" bash "$GXSHIP" <<< "n" 2>&1) && rc=$? || rc=$?
eq "abort n: exit 0" "0" "$rc"
eq "abort n: status unchanged" "building" "$(get_meta_status "$T6")"
lacks "abort n: gxpush NOT called" "$(cat "$PUSH_LOG6" 2>/dev/null)" "--auto"

echo ""

# ─── 7. rebase conflict ───────────────────────────────────────────────────────

echo "=== 7. rebase conflict ==="

T7="$TMP/t7"
mkdir -p "$T7"
make_meta "$T7" "building"
MOCK_BIN7="$TMP/bin7"
make_mock_git "$MOCK_BIN7" 1   # rebase exits 1 → conflict
MOCK_PUSH7="$TMP/gxpush7"
PUSH_LOG7="$TMP/push7.log"
make_mock_gxpush "$MOCK_PUSH7" "$PUSH_LOG7"

out=$(cd "$T7" && env GX_BASE_BRANCH=main GXPUSH="$MOCK_PUSH7" PATH="$MOCK_BIN7:$PATH" bash "$GXSHIP" <<< "Y" 2>&1) && rc=$? || rc=$?
eq "conflict: exit 1" "1" "$rc"
contains "conflict: error message" "$out" "Conflict"
contains "conflict: re-run hint" "$out" "re-run gxship"
lacks "conflict: gxpush NOT called" "$(cat "$PUSH_LOG7" 2>/dev/null)" "--auto"
# Status should not be 'shipped' after conflict
status7=$(get_meta_status "$T7")
lacks "conflict: status not shipped" "$status7" "shipped"

echo ""

# ─── Results ──────────────────────────────────────────────────────────────────

echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="
[[ "$FAIL" -eq 0 ]]
