#!/usr/bin/env bash
# Tests for render-standup.sh
# Uses fixture JSON files — no real API calls are made.
# This is the full dry-run test that exercises the complete render pipeline.
#
# Usage: bash test-render-standup.sh
# Exit 0 = all tests passed. Exit 1 = one or more failed.

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPTS_DIR/standup/render-standup.sh"
FIXTURES="$(dirname "$0")/fixtures/standup"

DATA_FIXTURE="$FIXTURES/data.json"
PROSE_FIXTURE="$FIXTURES/prose.json"

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
    assert_fail "$desc (pattern '$pattern' not found)"
    echo "    Output (first 400 chars): ${text:0:400}"
  fi
}

assert_not_contains() {
  local text="$1" pattern="$2" desc="$3"
  if echo "$text" | grep -q "$pattern"; then
    assert_fail "$desc (pattern '$pattern' unexpectedly found)"
  else
    assert_pass "$desc"
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

# Write a variant of the prose fixture. $1 = output path, $2 = python statements mutating `p`.
mutate_prose() {
  python3 - "$PROSE_FIXTURE" "$1" "$2" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
exec(sys.argv[3])
json.dump(p, open(sys.argv[2], "w"))
PY
}

# Run the renderer on a mutated prose; sets RC and ERR.
run_variant() {
  local name="$1" code="$2"
  mutate_prose "$TMP/$name.json" "$code"
  set +e
  bash "$SCRIPT" "$DATA_FIXTURE" "$TMP/$name.json" >/dev/null 2>"$TMP/$name.err"
  RC=$?
  set -e
  ERR=$(cat "$TMP/$name.err")
}

# --- Test 1: script exists and is executable ---
echo "=== T1: script exists ==="
[ -f "$SCRIPT" ] && assert_pass "render-standup.sh exists" || assert_fail "render-standup.sh not found at $SCRIPT"
[ -x "$SCRIPT" ] && assert_pass "render-standup.sh is executable" || assert_fail "render-standup.sh is not executable"

# --- Test 2: full dry-run with fixtures ---
echo ""
echo "=== T2: full dry-run produces output ==="
set +e
OUT=$(bash "$SCRIPT" "$DATA_FIXTURE" "$PROSE_FIXTURE" 2>"$TMP/t2.err")
EXIT2=$?
set -e
assert_exit_zero "$EXIT2" "exits 0 with fixture inputs"
[ -n "$OUT" ] && assert_pass "output is non-empty" || { assert_fail "output is empty"; echo "  stderr: $(cat "$TMP/t2.err")"; }

# --- Test 3: three sections in order ---
echo ""
echo "=== T3: sections and order ==="
ORDER=$(echo "$OUT" | grep '^\*\*' | tr '\n' '|')
assert_eq "$ORDER" "**Shipped since last standup** 🚀|**In flight** ⚡|**Blockers** 🚧|" "Shipped, In flight, Blockers in order"
assert_not_contains "$OUT" "## " "no old-style ## headers"
assert_not_contains "$OUT" "Talk track" "no old talk track section"

# --- Test 4: lead sentence follows each header ---
echo ""
echo "=== T4: lead sentences ==="
LEADS=$(echo "$OUT" | grep -A1 '^\*\*' | grep -v '^\*\*' | grep -v '^--$' | tr '\n' '|')
assert_eq "$LEADS" "Feature X landed since last standup and is live for Platform Reliability.|The dispatch redesign is one review pass from landing.|One item, and it is in my hands.|" "each header followed by its lead"

# --- Test 5: tokens become clickable links ---
echo ""
echo "=== T5: links ==="
assert_contains "$OUT" "^- Feature X is in users' hands behind the platform flag (\[SM-3011\](https://linear.app/sm/issue/SM-3011), \[#105\](" "ticket and PR tokens link in shipped"
assert_contains "$OUT" "^- Addressing requested changes on \[#101\](https://github.com/owner/repo/pull/101) (\[SM-3008\](" "blocker bullet links PR and ticket"
assert_not_contains "$OUT" "{SM-" "no raw ticket tokens left"
assert_not_contains "$OUT" "{#" "no raw PR tokens left"

# --- Test 6: shipped header falls back when nothing is new ---
echo ""
echo "=== T6: Shipped this cycle header ==="
python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
d['done_earlier'], d['done_new'] = d['done_new'], []
json.dump(d, open(sys.argv[2], 'w'))
" "$DATA_FIXTURE" "$TMP/data_earlier.json"
OUT6=$(bash "$SCRIPT" "$TMP/data_earlier.json" "$PROSE_FIXTURE" 2>/dev/null)
assert_contains "$OUT6" "^\*\*Shipped this cycle\*\* 🚀" "header reads Shipped this cycle when done_new is empty"

# --- Test 7: validation failures ---
echo ""
echo "=== T7: validation ==="
run_variant bare "p['in_flight']['items'][0] = 'Event loop work SM-3008'"
assert_eq "$RC" "1" "bare ticket reference exits 1"
assert_contains "$ERR" "bare reference 'SM-3008'" "bare ticket reference named in error"

run_variant barepr "p['blockers']['items'][0] = 'Addressing feedback on #101 ({#101})'"
assert_contains "$ERR" "bare reference '#101'" "bare PR reference rejected"

run_variant unknown "p['in_flight']['items'][0] = 'Mystery ({SM-9999})'"
assert_eq "$RC" "1" "unknown ticket exits 1"
assert_contains "$ERR" "unknown ticket {SM-9999}" "unknown ticket named in error"

run_variant emdash "p['shipped']['lead'] = 'Feature X shipped — nice.'"
assert_contains "$ERR" "em dash not allowed" "em dash rejected"

run_variant nolead "p['in_flight']['lead'] = ''"
assert_contains "$ERR" "in_flight: lead sentence is required" "missing lead rejected"

run_variant missingshipped "p['shipped']['items'] = ['Feature X ({#105})']"
assert_contains "$ERR" "done_new ticket SM-3011 is not referenced" "unreferenced done_new ticket rejected"

run_variant noshipped "p['shipped']['items'] = []"
assert_contains "$ERR" "shipped: items are required" "empty shipped rejected when work shipped"

run_variant missingblocker "p['blockers']['items'] = ['All clear ({SM-3008})']"
assert_contains "$ERR" "changes_requested PR #101 is not referenced" "unreferenced blocker PR rejected"

run_variant long "p['in_flight']['items'][0] = ' '.join(['word'] * 31) + ' ({SM-3008})'"
assert_contains "$ERR" "31 words (max 30)" "over-30-word item rejected"

run_variant toomany "p['blockers']['items'] = ['Item {#101}'] * 7"
assert_contains "$ERR" "blockers: 7 items (max 6)" "too many blocker items rejected"

run_variant nosection "del p['in_flight']"
assert_contains "$ERR" "in_flight: missing section object" "missing section rejected"

# --- Test 8: missing input files ---
echo ""
echo "=== T8: error on missing files ==="
set +e
bash "$SCRIPT" "/nonexistent/data.json" "$PROSE_FIXTURE" 2>/dev/null
EXIT8=$?
set -e
[ "$EXIT8" -ne 0 ] && assert_pass "exits non-zero when data_json not found" || assert_fail "should fail when data_json missing"

# --- Results ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
