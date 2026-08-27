#!/usr/bin/env bash
# gxclean.test.sh — Tests for gxclean merged branch cleanup + --full flag
# What: characterization tests for existing behavior + tests for --full Pass 1 (worktrees)
#       and Pass 2 (stale remote branch pruning)
# When: after changing gxclean

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GXCLEAN="$SCRIPT_DIR/gxclean"

PASS=0
FAIL=0
ok()       { echo "  PASS: $1"; PASS=$((PASS + 1)); }
no()       { echo "  FAIL: $1"; echo "        $2"; FAIL=$((FAIL + 1)); }
contains() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else no "$1" "missing [$3] in output"; fi; }
lacks()    { if [[ "$2" != *"$3"* ]]; then ok "$1"; else no "$1" "unexpected [$3] in output"; fi; }

# ---------------------------------------------------------------------------
# Temp dir — all stub state lives here
# ---------------------------------------------------------------------------
ROOT=$(mktemp -d)
trap 'chmod -R u+w "$ROOT" 2>/dev/null; rm -rf "$ROOT"' EXIT

STUB_BIN="$ROOT/bin"
CALLS_DIR="$ROOT/calls"
mkdir -p "$STUB_BIN" "$CALLS_DIR"
export ROOT STUB_BIN CALLS_DIR

# ---------------------------------------------------------------------------
# Stubs — use single-quoted heredoc so runtime env vars ($CALLS_DIR etc.)
# are evaluated when the stub runs, not when it is written.
# ---------------------------------------------------------------------------
make_git_stub() {
  cat > "$STUB_BIN/git" <<'GITEOF'
#!/usr/bin/env bash
CMD="$1"; shift
case "$CMD" in
  rev-parse)
    echo "${STUB_CURRENT_BRANCH:-feat/my-branch}"
    ;;
  branch)
    if [[ "$1" == "--merged" ]]; then
      cat "${STUB_MERGED_FILE:-/dev/null}" 2>/dev/null || true
    elif [[ "$1" == "-d" ]]; then
      echo "$2" >> "${CALLS_DIR}/branch_d"
    elif [[ "$1" == "-r" ]]; then
      cat "${STUB_BRANCH_R_FILE:-/dev/null}" 2>/dev/null || true
    else
      cat "${STUB_LOCAL_BRANCHES_FILE:-/dev/null}" 2>/dev/null || true
    fi
    ;;
  worktree)
    if [[ "$1" == "list" ]]; then
      cat "${STUB_WORKTREE_FILE:-/dev/null}" 2>/dev/null || true
    fi
    ;;
  fetch)
    echo "fetch_called" >> "${CALLS_DIR}/fetch"
    ;;
  push)
    shift  # skip "origin"
    shift  # skip "--delete"
    echo "$1" >> "${CALLS_DIR}/push_delete"
    ;;
  *) exit 0 ;;
esac
GITEOF
  chmod +x "$STUB_BIN/git"
}

make_wt_stub() {
  cat > "$STUB_BIN/wt" <<'WTEOF'
#!/usr/bin/env bash
if [[ "$1" == "rm" ]]; then
  echo "$2" >> "${CALLS_DIR}/wt_rm"
fi
WTEOF
  chmod +x "$STUB_BIN/wt"
}

reset_calls() {
  rm -f "$CALLS_DIR/branch_d" "$CALLS_DIR/wt_rm" "$CALLS_DIR/fetch" "$CALLS_DIR/push_delete"
}

# ---------------------------------------------------------------------------
# run_gxclean <stdin_text> [gxclean-args...]
# All STUB_* vars must be exported before calling.
# ---------------------------------------------------------------------------
run_gxclean() {
  local stdin_text="$1"; shift
  echo "$stdin_text" | \
    PATH="$STUB_BIN:$PATH" \
    GX_POLICY_FILE="/nonexistent" \
    GX_BASE_BRANCH="main" \
    CALLS_DIR="$CALLS_DIR" \
    bash "$GXCLEAN" "$@" 2>&1
}

# ============================================================
echo "=== gxclean — characterization tests (existing behavior) ==="
echo ""

# --- Test 1: no merged branches ---
echo "1. No merged branches -> prints message and exits cleanly"
make_git_stub
reset_calls
export STUB_MERGED_FILE="$ROOT/empty.txt"; > "$STUB_MERGED_FILE"
OUT=$(run_gxclean "")
contains "no-merged message shown" "$OUT" "No merged branches to clean up."
lacks "no delete prompt shown" "$OUT" "Delete all?"
unset STUB_MERGED_FILE
echo ""

# --- Test 2: merged branches listed ---
echo "2. Merged branches are listed with count"
make_git_stub
reset_calls
printf "  feat/old\n  feat/stale\n" > "$ROOT/merged.txt"
export STUB_MERGED_FILE="$ROOT/merged.txt"
OUT=$(run_gxclean "n")
contains "branch list header shown" "$OUT" "MERGED BRANCHES (2)"
contains "feat/old listed" "$OUT" "feat/old"
contains "feat/stale listed" "$OUT" "feat/stale"
contains "delete prompt shown" "$OUT" "Delete all? [Y/n]"
unset STUB_MERGED_FILE
echo ""

# --- Test 3: decline prompt -> aborted ---
echo "3. Answering n to Delete all? aborts without deleting"
make_git_stub
reset_calls
printf "  feat/old\n" > "$ROOT/merged.txt"
export STUB_MERGED_FILE="$ROOT/merged.txt"
OUT=$(run_gxclean "n")
contains "aborted message" "$OUT" "Aborted."
BRANCH_D_CALLS=$(cat "$CALLS_DIR/branch_d" 2>/dev/null || echo "")
if [[ -z "$BRANCH_D_CALLS" ]]; then ok "no branch -d called after n"; else no "no branch -d called after n" "got: $BRANCH_D_CALLS"; fi
unset STUB_MERGED_FILE
echo ""

# --- Test 4: accept prompt -> deletes branches ---
echo "4. Answering Y deletes each merged branch"
make_git_stub
reset_calls
printf "  feat/old\n  feat/stale\n" > "$ROOT/merged.txt"
export STUB_MERGED_FILE="$ROOT/merged.txt"
OUT=$(run_gxclean "Y")
contains "deleted message for feat/old" "$OUT" "Deleted"
BRANCH_D_CALLS=$(cat "$CALLS_DIR/branch_d" 2>/dev/null || echo "")
contains "branch -d feat/old recorded" "$BRANCH_D_CALLS" "feat/old"
contains "branch -d feat/stale recorded" "$BRANCH_D_CALLS" "feat/stale"
unset STUB_MERGED_FILE
echo ""

# --- Test 5: prototype/* branch gets [PRIORITY] label ---
echo "5. prototype/* branches show [PRIORITY] label"
make_git_stub
reset_calls
printf "  prototype/my-exp\n" > "$ROOT/merged.txt"
export STUB_MERGED_FILE="$ROOT/merged.txt"
OUT=$(run_gxclean "n")
contains "PRIORITY label present" "$OUT" "[PRIORITY]"
unset STUB_MERGED_FILE
echo ""

# --- Test 6: WARN shown when on base branch ---
echo "6. WARN shown when current branch is base"
make_git_stub
reset_calls
> "$ROOT/empty2.txt"
export STUB_MERGED_FILE="$ROOT/empty2.txt"
export STUB_CURRENT_BRANCH="main"
OUT=$(run_gxclean "")
contains "WARN message shown" "$OUT" "WARN: currently on base branch (main)"
unset STUB_MERGED_FILE STUB_CURRENT_BRANCH
echo ""

# ============================================================
echo "=== gxclean --full — Pass 1: worktree cleanup ==="
echo ""

# --- Test 7: merged worktree -> prompts, Y removes it ---
echo "7. Merged worktree: Y answer calls wt rm"
make_git_stub
make_wt_stub
reset_calls
> "$ROOT/no_merged.txt"
export STUB_MERGED_FILE="$ROOT/no_merged.txt"
cat > "$ROOT/worktrees.txt" <<'EOF'
worktree /repos/main
HEAD abc123
branch refs/heads/main

worktree /repos/feat-done
HEAD def456
branch refs/heads/feat/done

EOF
# The git stub for --merged returns "feat/done" when STUB_MERGED_FILE is set.
# But for worktree pass, it calls "git branch --merged origin/main" to check if
# the worktree branch is merged. We need feat/done to be in the merged list.
printf "  feat/done\n" > "$ROOT/merged_wt.txt"
export STUB_MERGED_FILE="$ROOT/merged_wt.txt"
export STUB_WORKTREE_FILE="$ROOT/worktrees.txt"
# Pipe: "Y" for both merged-branch pass and worktree pass
# merged-branch pass will see feat/done, prompt "Delete all?" -> we answer Y
# worktree pass will see feat/done worktree, prompt "Remove?" -> Y
OUT=$(printf 'Y\nY\n' | \
  PATH="$STUB_BIN:$PATH" \
  GX_POLICY_FILE="/nonexistent" \
  GX_BASE_BRANCH="main" \
  CALLS_DIR="$CALLS_DIR" \
  STUB_MERGED_FILE="$ROOT/merged_wt.txt" \
  STUB_WORKTREE_FILE="$ROOT/worktrees.txt" \
  bash "$GXCLEAN" --full 2>&1)
contains "worktree pass header" "$OUT" "Pass 1: merged worktrees"
contains "worktree path shown" "$OUT" "/repos/feat-done"
contains "branch shown" "$OUT" "feat/done"
contains "remove prompt shown" "$OUT" "Remove? [Y/n]"
WT_RM_CALLS=$(cat "$CALLS_DIR/wt_rm" 2>/dev/null || echo "")
contains "wt rm called for path" "$WT_RM_CALLS" "/repos/feat-done"
unset STUB_MERGED_FILE STUB_WORKTREE_FILE
echo ""

# --- Test 8: non-merged worktree -> not prompted ---
echo "8. Non-merged worktree: not prompted"
make_git_stub
make_wt_stub
reset_calls
> "$ROOT/no_merged8.txt"
cat > "$ROOT/worktrees_active.txt" <<'EOF'
worktree /repos/main
HEAD abc123
branch refs/heads/main

worktree /repos/active
HEAD 999abc
branch refs/heads/feat/active

EOF
OUT=$(STUB_MERGED_FILE="$ROOT/no_merged8.txt" \
  STUB_WORKTREE_FILE="$ROOT/worktrees_active.txt" \
  PATH="$STUB_BIN:$PATH" \
  GX_POLICY_FILE="/nonexistent" \
  GX_BASE_BRANCH="main" \
  CALLS_DIR="$CALLS_DIR" \
  bash "$GXCLEAN" --full <<< "" 2>&1)
lacks "active worktree not prompted" "$OUT" "/repos/active"
contains "no merged worktrees message" "$OUT" "No merged worktrees to remove."
echo ""

# --- Test 9: decline worktree removal -> skips only that item ---
echo "9. Answering n to Remove? skips worktree, continues"
make_git_stub
make_wt_stub
reset_calls
printf "  feat/done\n  feat/also-done\n" > "$ROOT/two_merged.txt"
cat > "$ROOT/two_worktrees.txt" <<'EOF'
worktree /repos/main
HEAD abc123
branch refs/heads/main

worktree /repos/wt1
HEAD def456
branch refs/heads/feat/done

worktree /repos/wt2
HEAD ghi789
branch refs/heads/feat/also-done

EOF
# Pipe: Y for merged-branch delete-all, n for first worktree, Y for second
OUT=$(printf 'Y\nn\nY\n' | \
  PATH="$STUB_BIN:$PATH" \
  GX_POLICY_FILE="/nonexistent" \
  GX_BASE_BRANCH="main" \
  CALLS_DIR="$CALLS_DIR" \
  STUB_MERGED_FILE="$ROOT/two_merged.txt" \
  STUB_WORKTREE_FILE="$ROOT/two_worktrees.txt" \
  bash "$GXCLEAN" --full 2>&1)
WT_RM_CALLS=$(cat "$CALLS_DIR/wt_rm" 2>/dev/null || echo "")
lacks "first worktree skipped" "$WT_RM_CALLS" "/repos/wt1"
contains "second worktree removed" "$WT_RM_CALLS" "/repos/wt2"
echo ""

# ============================================================
echo "=== gxclean --full — Pass 2: stale remote branch pruning ==="
echo ""

# --- Test 10: stale remote branch -> prompts, Y calls git push --delete ---
echo "10. Stale remote branch: Y answer calls git push origin --delete"
make_git_stub
make_wt_stub
reset_calls
> "$ROOT/no_merged10.txt"
> "$ROOT/no_worktrees10.txt"
printf "  origin/feat/stale-remote\n" > "$ROOT/remote_branches.txt"
printf "  main\n" > "$ROOT/local_branches.txt"
OUT=$(printf 'Y\n' | \
  PATH="$STUB_BIN:$PATH" \
  GX_POLICY_FILE="/nonexistent" \
  GX_BASE_BRANCH="main" \
  CALLS_DIR="$CALLS_DIR" \
  STUB_MERGED_FILE="$ROOT/no_merged10.txt" \
  STUB_WORKTREE_FILE="$ROOT/no_worktrees10.txt" \
  STUB_BRANCH_R_FILE="$ROOT/remote_branches.txt" \
  STUB_LOCAL_BRANCHES_FILE="$ROOT/local_branches.txt" \
  bash "$GXCLEAN" --full 2>&1)
contains "pass 2 header shown" "$OUT" "Pass 2: stale remote branches"
contains "prune prompt shown" "$OUT" "Prune remote"
contains "origin/feat/stale-remote in prompt" "$OUT" "origin/feat/stale-remote"
PUSH_DELETE_CALLS=$(cat "$CALLS_DIR/push_delete" 2>/dev/null || echo "")
contains "push --delete called for branch" "$PUSH_DELETE_CALLS" "feat/stale-remote"
echo ""

# --- Test 11: remote branch with matching local -> not prompted ---
echo "11. Remote branch with local counterpart: not prompted"
make_git_stub
make_wt_stub
reset_calls
> "$ROOT/no_merged11.txt"
> "$ROOT/no_worktrees11.txt"
printf "  origin/feat/active\n" > "$ROOT/remote_branches2.txt"
printf "  main\n  feat/active\n" > "$ROOT/local_branches2.txt"
OUT=$(printf '' | \
  PATH="$STUB_BIN:$PATH" \
  GX_POLICY_FILE="/nonexistent" \
  GX_BASE_BRANCH="main" \
  CALLS_DIR="$CALLS_DIR" \
  STUB_MERGED_FILE="$ROOT/no_merged11.txt" \
  STUB_WORKTREE_FILE="$ROOT/no_worktrees11.txt" \
  STUB_BRANCH_R_FILE="$ROOT/remote_branches2.txt" \
  STUB_LOCAL_BRANCHES_FILE="$ROOT/local_branches2.txt" \
  bash "$GXCLEAN" --full 2>&1)
lacks "active remote not prompted" "$OUT" "Prune remote origin/feat/active"
contains "no stale message" "$OUT" "No stale remote branches to prune."
echo ""

# --- Test 12: decline remote prune -> skips only that branch ---
echo "12. Answering n to prune prompt skips only that branch"
make_git_stub
make_wt_stub
reset_calls
> "$ROOT/no_merged12.txt"
> "$ROOT/no_worktrees12.txt"
printf "  origin/feat/old\n  origin/feat/also-old\n" > "$ROOT/two_remotes.txt"
printf "  main\n" > "$ROOT/local_only_main.txt"
OUT=$(printf 'n\nY\n' | \
  PATH="$STUB_BIN:$PATH" \
  GX_POLICY_FILE="/nonexistent" \
  GX_BASE_BRANCH="main" \
  CALLS_DIR="$CALLS_DIR" \
  STUB_MERGED_FILE="$ROOT/no_merged12.txt" \
  STUB_WORKTREE_FILE="$ROOT/no_worktrees12.txt" \
  STUB_BRANCH_R_FILE="$ROOT/two_remotes.txt" \
  STUB_LOCAL_BRANCHES_FILE="$ROOT/local_only_main.txt" \
  bash "$GXCLEAN" --full 2>&1)
PUSH_DELETE_CALLS=$(cat "$CALLS_DIR/push_delete" 2>/dev/null || echo "")
lacks "first remote skipped" "$PUSH_DELETE_CALLS" "feat/old"
contains "second remote pruned" "$PUSH_DELETE_CALLS" "feat/also-old"
echo ""

# --- Test 13: git fetch --prune is called during Pass 2 ---
echo "13. git fetch --prune is called during --full Pass 2"
make_git_stub
make_wt_stub
reset_calls
> "$ROOT/no_merged13.txt"
> "$ROOT/no_worktrees13.txt"
> "$ROOT/no_remotes13.txt"
printf '' | \
  PATH="$STUB_BIN:$PATH" \
  GX_POLICY_FILE="/nonexistent" \
  GX_BASE_BRANCH="main" \
  CALLS_DIR="$CALLS_DIR" \
  STUB_MERGED_FILE="$ROOT/no_merged13.txt" \
  STUB_WORKTREE_FILE="$ROOT/no_worktrees13.txt" \
  STUB_BRANCH_R_FILE="$ROOT/no_remotes13.txt" \
  bash "$GXCLEAN" --full >/dev/null 2>&1
FETCH_CALLS=$(cat "$CALLS_DIR/fetch" 2>/dev/null || echo "")
contains "fetch was called" "$FETCH_CALLS" "fetch_called"
echo ""

# --- Test 14: --full not supplied -> no worktree/remote pass ---
echo "14. Without --full, Pass 1 and Pass 2 are not run"
make_git_stub
make_wt_stub
reset_calls
> "$ROOT/no_merged14.txt"
OUT=$(printf '' | \
  PATH="$STUB_BIN:$PATH" \
  GX_POLICY_FILE="/nonexistent" \
  GX_BASE_BRANCH="main" \
  CALLS_DIR="$CALLS_DIR" \
  STUB_MERGED_FILE="$ROOT/no_merged14.txt" \
  bash "$GXCLEAN" 2>&1)
lacks "no pass 1 header" "$OUT" "Pass 1: merged worktrees"
lacks "no pass 2 header" "$OUT" "Pass 2: stale remote branches"
FETCH_CALLS=$(cat "$CALLS_DIR/fetch" 2>/dev/null || echo "")
if [[ -z "$FETCH_CALLS" ]]; then ok "no fetch without --full"; else no "no fetch without --full" "fetch called"; fi
echo ""

# ============================================================
echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="
[[ "$FAIL" -eq 0 ]]
