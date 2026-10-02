#!/usr/bin/env bash
# resolve-standups-dir.sh — resolve the absolute path to Quaestor-Web's standups dir.
#
# Usage: resolve-standups-dir.sh [--ensure]
#
# Resolution order:
#   1. If the cwd repo's `origin` remote matches Quaestor-Technologies/Quaestor-Web,
#      derive the MAIN worktree root from `git rev-parse --git-common-dir` and use
#      <root>/docs/standups.
#   2. $QUAESTOR_WEB_DIR env var, if set, use <$QUAESTOR_WEB_DIR>/docs/standups.
#   3. Exit 1 with a one-line hint.
#
# --ensure mode:
#   Creates docs/standups/ and idempotently appends "docs/standups/" to
#   <git-common-dir>/info/exclude (exact-line match). Never touches .gitignore.
#
# Exit 0 and prints the absolute path on success.
# Exit 1 with a one-line hint to stderr on failure.

set -euo pipefail

ENSURE=false
for arg in "$@"; do
  if [[ "$arg" == "--ensure" ]]; then
    ENSURE=true
  fi
done

# ─── Resolve standups directory ───────────────────────────────────────────────

_repo_matches_quaestor() {
  local origin
  origin=$(git remote get-url origin 2>/dev/null || true)
  if echo "$origin" | grep -qi "Quaestor-Technologies/Quaestor-Web"; then
    return 0
  fi
  return 1
}

_main_worktree_root() {
  # git rev-parse --git-common-dir returns the common .git dir path.
  # For the main worktree: .git itself (an absolute or relative path).
  # For a linked worktree: <main_checkout>/.git
  local git_common_dir
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  # Make absolute
  if [[ "${git_common_dir:0:1}" != "/" ]]; then
    git_common_dir="$(pwd)/$git_common_dir"
  fi
  # Normalize: strip trailing /.git if present (the parent is the worktree root)
  # git_common_dir ends in ".git" for the main checkout
  local worktree_root
  worktree_root=$(dirname "$git_common_dir")
  printf '%s' "$worktree_root"
}

STANDUPS_DIR=""

if git rev-parse --git-dir >/dev/null 2>&1 && _repo_matches_quaestor; then
  STANDUPS_DIR="$(_main_worktree_root)/docs/standups"
elif [[ -n "${QUAESTOR_WEB_DIR:-}" ]]; then
  STANDUPS_DIR="${QUAESTOR_WEB_DIR}/docs/standups"
else
  echo "Cannot locate Quaestor-Web: run from the repo or set QUAESTOR_WEB_DIR=<path>" >&2
  exit 1
fi

# ─── --ensure: create dir and update exclude ──────────────────────────────────

if [[ "$ENSURE" == "true" ]]; then
  mkdir -p "$STANDUPS_DIR"

  # Find the git-common-dir for the exclude file
  local_git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null || true)
  if [[ -n "$local_git_common_dir" ]]; then
    if [[ "${local_git_common_dir:0:1}" != "/" ]]; then
      local_git_common_dir="$(pwd)/$local_git_common_dir"
    fi
    EXCLUDE_FILE="$local_git_common_dir/info/exclude"
    mkdir -p "$(dirname "$EXCLUDE_FILE")"
    # Idempotent: only append if the exact line is not already present
    if ! grep -qxF "docs/standups/" "$EXCLUDE_FILE" 2>/dev/null; then
      printf 'docs/standups/\n' >> "$EXCLUDE_FILE"
    fi
  fi
fi

printf '%s\n' "$STANDUPS_DIR"
