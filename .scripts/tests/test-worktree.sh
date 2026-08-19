#!/usr/bin/env bash
# Unit tests for the worktree engine script
#
# Tests mock all git calls so no real repo is needed.
# Each test uses WORKTREE_BASE to redirect the worktree directory into /tmp.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_SCRIPT="$SCRIPT_DIR/../worktree"

PASS=0
FAIL=0

# ─── Helpers ──────────────────────────────────────────────────────────────────

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

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "FAIL: $desc (unexpected match)"
    echo "  found:  $needle"
    echo "  in:     $haystack"
    ((FAIL++))
  else
    echo "PASS: $desc"
    ((PASS++))
  fi
}

# Set up a fresh mock environment for each test
setup_mock_env() {
  MOCK_BIN_DIR=$(mktemp -d)
  TEST_WORKTREES=$(mktemp -d)
  cp "$SCRIPT_DIR/.mock-git" "$MOCK_BIN_DIR/git"
  chmod +x "$MOCK_BIN_DIR/git"
}

teardown_mock_env() {
  rm -rf "$MOCK_BIN_DIR" "$TEST_WORKTREES"
}

run_wt() {
  # run_wt [extra env vars] -- <args>
  # Returns stdout; stderr is captured in RUN_STDERR
  local env_vars=""
  local args=()
  local reading_env=true
  for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
      reading_env=false
      continue
    fi
    if $reading_env; then
      env_vars="$env_vars $arg"
    else
      args+=("$arg")
    fi
  done

  local tmpout tmperr
  tmpout=$(mktemp)
  tmperr=$(mktemp)

  eval "env PATH=\"\$MOCK_BIN_DIR:\$PATH\" \
    WORKTREE_BASE=\"\$TEST_WORKTREES\" \
    MOCK_TOPLEVEL=/fake/myrepo \
    $env_vars \
    \"$WORKTREE_SCRIPT\" ${args[*]@Q}" >"$tmpout" 2>"$tmperr"
  RUN_EXIT=$?
  RUN_STDOUT=$(cat "$tmpout")
  RUN_STDERR=$(cat "$tmperr")
  rm -f "$tmpout" "$tmperr"
}

# ─── Guard: script must be executable ─────────────────────────────────────────

if [[ -x "$WORKTREE_SCRIPT" ]]; then
  echo "PASS: worktree script is executable"
  ((PASS++))
else
  echo "FAIL: worktree script is not executable (path: $WORKTREE_SCRIPT)"
  ((FAIL++))
fi

# ─── Case 1: Existing worktree folder ─────────────────────────────────────────

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/existing"
run_wt -- feat/existing
assert_eq "case1: exit code 0" "0" "$RUN_EXIT"
assert_eq "case1: stdout is worktree path" "$TEST_WORKTREES/myrepo/feat/existing" "$RUN_STDOUT"
assert_contains "case1: stderr says attaching" "attaching to existing branch feat/existing" "$RUN_STDERR"
teardown_mock_env

# ─── Case 2: Branch exists locally, no worktree folder ────────────────────────

setup_mock_env
run_wt "MOCK_LOCAL_BRANCHES=feat/local-branch" -- feat/local-branch
assert_eq "case2: exit code 0" "0" "$RUN_EXIT"
EXPECTED_PATH="$TEST_WORKTREES/myrepo/feat/local-branch"
assert_eq "case2: stdout is worktree path" "$EXPECTED_PATH" "$RUN_STDOUT"
if [[ -d "$EXPECTED_PATH" ]]; then
  echo "PASS: case2: worktree directory was created"
  ((PASS++))
else
  echo "FAIL: case2: worktree directory was not created ($EXPECTED_PATH)"
  ((FAIL++))
fi
teardown_mock_env

# ─── Case 3: Branch exists on remote only ─────────────────────────────────────

setup_mock_env
run_wt "MOCK_REMOTE_BRANCHES=feat/remote-branch" -- feat/remote-branch
assert_eq "case3: exit code 0" "0" "$RUN_EXIT"
EXPECTED_PATH="$TEST_WORKTREES/myrepo/feat/remote-branch"
assert_eq "case3: stdout is worktree path" "$EXPECTED_PATH" "$RUN_STDOUT"
if [[ -d "$EXPECTED_PATH" ]]; then
  echo "PASS: case3: worktree directory was created after remote fetch"
  ((PASS++))
else
  echo "FAIL: case3: worktree directory was not created ($EXPECTED_PATH)"
  ((FAIL++))
fi
teardown_mock_env

# ─── Case 4a: Branch exists nowhere — user confirms Y ─────────────────────────

setup_mock_env
GIT_CALL_LOG=$(mktemp)
run_wt "GIT_CALL_LOG=$GIT_CALL_LOG" -- <<< "Y"
# Can't use <<< with run_wt easily; run directly
RUN_STDOUT=$(echo "Y" | env \
  PATH="$MOCK_BIN_DIR:$PATH" \
  WORKTREE_BASE="$TEST_WORKTREES" \
  MOCK_TOPLEVEL=/fake/myrepo \
  GIT_CALL_LOG="$GIT_CALL_LOG" \
  "$WORKTREE_SCRIPT" "feat/new-branch" 2>/tmp/wt-test-stderr-4a)
RUN_EXIT=$?
RUN_STDERR=$(cat /tmp/wt-test-stderr-4a)

assert_eq "case4a: exit code 0" "0" "$RUN_EXIT"
EXPECTED_PATH="$TEST_WORKTREES/myrepo/feat/new-branch"
assert_eq "case4a: stdout is worktree path" "$EXPECTED_PATH" "$RUN_STDOUT"
assert_contains "case4a: stderr shows Y/n prompt" "[Y/n]" "$RUN_STDERR"
if [[ -d "$EXPECTED_PATH" ]]; then
  echo "PASS: case4a: worktree directory was created"
  ((PASS++))
else
  echo "FAIL: case4a: worktree directory was not created ($EXPECTED_PATH)"
  ((FAIL++))
fi
rm -f "$GIT_CALL_LOG" /tmp/wt-test-stderr-4a
teardown_mock_env

# ─── Case 4b: Branch exists nowhere — user declines N ─────────────────────────

setup_mock_env
RUN_STDOUT=$(echo "n" | env \
  PATH="$MOCK_BIN_DIR:$PATH" \
  WORKTREE_BASE="$TEST_WORKTREES" \
  MOCK_TOPLEVEL=/fake/myrepo \
  "$WORKTREE_SCRIPT" "feat/declined-branch" 2>/dev/null)
RUN_EXIT=$?

assert_eq "case4b: exit code 2 (declined)" "2" "$RUN_EXIT"
assert_eq "case4b: stdout is empty when declined" "" "$RUN_STDOUT"
teardown_mock_env

# ─── Missing prefix warning ────────────────────────────────────────────────────

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/my-branch-no-prefix"
run_wt -- my-branch-no-prefix
assert_contains "prefix warn: stderr has WARN" "WARN" "$RUN_STDERR"
assert_contains "prefix warn: mentions feat/fix/spike" "feat/" "$RUN_STDERR"
teardown_mock_env

# ─── No prefix warning when prefix is present ─────────────────────────────────

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/good-prefix"
run_wt -- feat/good-prefix
assert_not_contains "good prefix: no WARN on stderr" "WARN" "$RUN_STDERR"
teardown_mock_env

# ─── Base override ─────────────────────────────────────────────────────────────

setup_mock_env
GIT_CALL_LOG=$(mktemp)
echo "Y" | env \
  PATH="$MOCK_BIN_DIR:$PATH" \
  WORKTREE_BASE="$TEST_WORKTREES" \
  MOCK_TOPLEVEL=/fake/myrepo \
  GIT_CALL_LOG="$GIT_CALL_LOG" \
  "$WORKTREE_SCRIPT" "feat/x" "develop" >/dev/null 2>&1
RUN_EXIT=$?
assert_eq "base-override: exit code 0" "0" "$RUN_EXIT"
if grep -q "develop" "$GIT_CALL_LOG"; then
  echo "PASS: base-override: git worktree add called with 'develop'"
  ((PASS++))
else
  echo "FAIL: base-override: 'develop' not found in git call log"
  echo "  git calls were:"
  cat "$GIT_CALL_LOG" | sed 's/^/    /'
  ((FAIL++))
fi
rm -f "$GIT_CALL_LOG"
teardown_mock_env

# ─── Header check ─────────────────────────────────────────────────────────────

HEADER_LINES=$(head -5 "$WORKTREE_SCRIPT" | grep '^#' | grep -v '^#!/')
HEADER_COUNT=$(echo "$HEADER_LINES" | grep -c '^#')
if [[ "$HEADER_COUNT" -ge 3 ]]; then
  echo "PASS: engine script has 3+ header comment lines"
  ((PASS++))
else
  echo "FAIL: engine script has fewer than 3 header comment lines (found $HEADER_COUNT)"
  ((FAIL++))
fi
if echo "$HEADER_LINES" | grep -q 'What:'; then
  echo "PASS: header includes What: line"
  ((PASS++))
else
  echo "FAIL: header missing What: line"
  ((FAIL++))
fi
if echo "$HEADER_LINES" | grep -q 'When:'; then
  echo "PASS: header includes When: line"
  ((PASS++))
else
  echo "FAIL: header missing When: line"
  ((FAIL++))
fi

# ─── wt function check ────────────────────────────────────────────────────────

ZSHRC="$SCRIPT_DIR/../../.zshrc"
if grep -q 'function wt\|^wt()' "$ZSHRC"; then
  echo "PASS: wt function is defined in .zshrc"
  ((PASS++))
else
  echo "FAIL: wt function not found in .zshrc"
  ((FAIL++))
fi

# ─── wt ls: lists worktrees for current repo ─────────────────────────────────

setup_mock_env
# Create two worktrees with .git files so ls can find them
mkdir -p "$TEST_WORKTREES/myrepo/feat/alpha"
echo "gitdir: /fake" > "$TEST_WORKTREES/myrepo/feat/alpha/.git"
mkdir -p "$TEST_WORKTREES/myrepo/fix/beta"
echo "gitdir: /fake" > "$TEST_WORKTREES/myrepo/fix/beta/.git"
run_wt -- ls
assert_eq "ls: exit code 0" "0" "$RUN_EXIT"
assert_eq "ls: stdout is empty (output goes to stderr)" "" "$RUN_STDOUT"
assert_contains "ls: stderr contains repo name" "myrepo" "$RUN_STDERR"
assert_contains "ls: stderr lists feat/alpha" "feat/alpha" "$RUN_STDERR"
assert_contains "ls: stderr lists fix/beta" "fix/beta" "$RUN_STDERR"
teardown_mock_env

# ─── wt ls: empty repo shows (none) ──────────────────────────────────────────

setup_mock_env
run_wt -- ls
assert_eq "ls-empty: exit code 0" "0" "$RUN_EXIT"
assert_contains "ls-empty: stderr shows (none)" "(none)" "$RUN_STDERR"
teardown_mock_env

# ─── wt ls --all: lists across all repos ─────────────────────────────────────

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/one"
echo "gitdir: /fake" > "$TEST_WORKTREES/myrepo/feat/one/.git"
mkdir -p "$TEST_WORKTREES/otherrepo/fix/two"
echo "gitdir: /fake" > "$TEST_WORKTREES/otherrepo/fix/two/.git"
run_wt -- ls --all
assert_eq "ls-all: exit code 0" "0" "$RUN_EXIT"
assert_contains "ls-all: stderr lists myrepo/feat/one" "myrepo/feat/one" "$RUN_STDERR"
assert_contains "ls-all: stderr lists otherrepo/fix/two" "otherrepo/fix/two" "$RUN_STDERR"
teardown_mock_env

# ─── wt rm: success on clean worktree ─────────────────────────────────────────

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/clean"
echo "gitdir: /fake" > "$TEST_WORKTREES/myrepo/feat/clean/.git"
run_wt -- rm feat/clean
assert_eq "rm-clean: exit code 0" "0" "$RUN_EXIT"
assert_contains "rm-clean: stderr confirms removal" "Removed" "$RUN_STDERR"
if [[ ! -d "$TEST_WORKTREES/myrepo/feat/clean" ]]; then
  echo "PASS: rm-clean: worktree directory was removed"
  ((PASS++))
else
  echo "FAIL: rm-clean: worktree directory still exists after rm"
  ((FAIL++))
fi
teardown_mock_env

# ─── wt rm: blocked on uncommitted changes ────────────────────────────────────

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/dirty"
echo "gitdir: /fake" > "$TEST_WORKTREES/myrepo/feat/dirty/.git"
run_wt "MOCK_PORCELAIN=dirty" -- rm feat/dirty
assert_eq "rm-dirty: exit code 1" "1" "$RUN_EXIT"
assert_contains "rm-dirty: stderr mentions uncommitted changes" "uncommitted changes" "$RUN_STDERR"
if [[ -d "$TEST_WORKTREES/myrepo/feat/dirty" ]]; then
  echo "PASS: rm-dirty: worktree directory preserved (not removed)"
  ((PASS++))
else
  echo "FAIL: rm-dirty: worktree directory was removed despite dirty state"
  ((FAIL++))
fi
teardown_mock_env

# ─── wt rm: blocked on unpushed commits ───────────────────────────────────────

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/unpushed"
echo "gitdir: /fake" > "$TEST_WORKTREES/myrepo/feat/unpushed/.git"
run_wt "MOCK_UNPUSHED=abc1234" -- rm feat/unpushed
assert_eq "rm-unpushed: exit code 1" "1" "$RUN_EXIT"
assert_contains "rm-unpushed: stderr mentions unpushed commits" "unpushed commits" "$RUN_STDERR"
if [[ -d "$TEST_WORKTREES/myrepo/feat/unpushed" ]]; then
  echo "PASS: rm-unpushed: worktree directory preserved (not removed)"
  ((PASS++))
else
  echo "FAIL: rm-unpushed: worktree directory was removed despite unpushed commits"
  ((FAIL++))
fi
teardown_mock_env

# ─── wt rm --force: removes despite uncommitted changes ───────────────────────

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/force-dirty"
echo "gitdir: /fake" > "$TEST_WORKTREES/myrepo/feat/force-dirty/.git"
run_wt "MOCK_PORCELAIN=dirty" -- rm feat/force-dirty --force
assert_eq "rm-force: exit code 0" "0" "$RUN_EXIT"
if [[ ! -d "$TEST_WORKTREES/myrepo/feat/force-dirty" ]]; then
  echo "PASS: rm-force: worktree directory removed despite dirty state"
  ((PASS++))
else
  echo "FAIL: rm-force: worktree directory still exists after rm --force"
  ((FAIL++))
fi
teardown_mock_env

# ─── bare wt: prints help + ls ────────────────────────────────────────────────

setup_mock_env
run_wt --
assert_eq "bare: exit code 0" "0" "$RUN_EXIT"
assert_eq "bare: stdout is empty" "" "$RUN_STDOUT"
assert_contains "bare: stderr shows USAGE section" "USAGE" "$RUN_STDERR"
assert_contains "bare: stderr shows wt ls entry" "wt ls" "$RUN_STDERR"
assert_contains "bare: stderr shows wt rm entry" "wt rm" "$RUN_STDERR"
assert_contains "bare: stderr shows Worktrees for" "Worktrees for" "$RUN_STDERR"
teardown_mock_env

# ─── wt -h: prints full command reference ─────────────────────────────────────

setup_mock_env
run_wt -- -h
assert_eq "help-h: exit code 0" "0" "$RUN_EXIT"
assert_eq "help-h: stdout is empty" "" "$RUN_STDOUT"
assert_contains "help-h: stderr shows USAGE" "USAGE" "$RUN_STDERR"
assert_contains "help-h: stderr shows wt ls" "wt ls" "$RUN_STDERR"
assert_contains "help-h: stderr shows wt rm" "wt rm" "$RUN_STDERR"
assert_contains "help-h: stderr shows WORKTREE LOCATION" "WORKTREE LOCATION" "$RUN_STDERR"
teardown_mock_env

# ─── wt --help: prints full command reference ─────────────────────────────────

setup_mock_env
run_wt -- --help
assert_eq "help-long: exit code 0" "0" "$RUN_EXIT"
assert_eq "help-long: stdout is empty" "" "$RUN_STDOUT"
assert_contains "help-long: stderr shows USAGE" "USAGE" "$RUN_STDERR"
assert_contains "help-long: stderr shows wt ls" "wt ls" "$RUN_STDERR"
assert_contains "help-long: stderr shows wt rm" "wt rm" "$RUN_STDERR"
teardown_mock_env

# ─── stdout purity: only the worktree path reaches stdout ────────────────────
# The wt zsh function cds to stdout, so every human-facing line must go to
# stderr. Dependency install and config link output must not leak in.

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/quiet"
run_wt -- feat/quiet
assert_eq "stdout-purity: exit code 0" "0" "$RUN_EXIT"
assert_eq "stdout-purity: stdout is just the path" "$TEST_WORKTREES/myrepo/feat/quiet" "$RUN_STDOUT"
assert_not_contains "stdout-purity: no install output on stdout" "installing deps" "$RUN_STDOUT"
assert_not_contains "stdout-purity: no link output on stdout" "linked local config" "$RUN_STDOUT"
teardown_mock_env

# ─── --no-install / --no-links are consumed, not treated as a branch ─────────

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/flags"
run_wt -- feat/flags --no-install --no-links
assert_eq "flags: exit code 0" "0" "$RUN_EXIT"
assert_eq "flags: stdout is the branch path, flags stripped" "$TEST_WORKTREES/myrepo/feat/flags" "$RUN_STDOUT"
teardown_mock_env

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/flags-first"
run_wt -- --no-links feat/flags-first
assert_eq "flags-first: flag before branch name still resolves" "$TEST_WORKTREES/myrepo/feat/flags-first" "$RUN_STDOUT"
teardown_mock_env

# ─── repo name comes from the MAIN worktree, not the current one ─────────────
# Running wt from inside a linked worktree must still nest under <repo>/, not
# under the leaf directory of the worktree you happen to be standing in.

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/from-worktree"
run_wt "MOCK_TOPLEVEL=/fake/worktrees/myrepo/feat/other" "MOCK_COMMON_DIR=/fake/myrepo/.git" -- feat/from-worktree
assert_eq "main-root: exit code 0" "0" "$RUN_EXIT"
assert_eq "main-root: nests under repo name, not worktree leaf" "$TEST_WORKTREES/myrepo/feat/from-worktree" "$RUN_STDOUT"
assert_not_contains "main-root: does not use the worktree leaf dir" "$TEST_WORKTREES/other/" "$RUN_STDOUT"
teardown_mock_env

setup_mock_env
mkdir -p "$TEST_WORKTREES/myrepo/feat/from-main"
run_wt -- feat/from-main
assert_eq "main-root: relative common dir keeps main-worktree behaviour" "$TEST_WORKTREES/myrepo/feat/from-main" "$RUN_STDOUT"
teardown_mock_env

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
