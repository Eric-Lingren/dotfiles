#!/bin/bash
# PostToolUse hook for EnterWorktree: install JS deps in new worktrees.
#
# Claude Code's isolation: "worktree" creates bare git worktrees at
# .claude/worktrees/agent-*. These have no node_modules, so pre-commit
# hooks (biome, eslint) and builds fail. This hook detects the package
# manager and runs install after worktree creation.
#
# Disable: export CLAUDE_WT_DEPS=0

[ "${CLAUDE_WT_DEPS:-1}" = "0" ] && exit 0

INPUT=$(cat)

# Try to get worktree path from tool input (existing worktree entry)
WT_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null)

# For new worktrees, construct path from name + git root
if [ -z "$WT_PATH" ] || [ ! -d "$WT_PATH" ]; then
  NAME=$(echo "$INPUT" | jq -r '.tool_input.name // empty' 2>/dev/null)
  if [ -n "$NAME" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
    [ -n "$ROOT" ] && WT_PATH="$ROOT/.claude/worktrees/$NAME"
  fi
fi

# Fall back to CWD (session switches into worktree after EnterWorktree)
if [ -z "$WT_PATH" ] || [ ! -d "$WT_PATH" ]; then
  WT_PATH="$PWD"
fi

[ -d "$WT_PATH" ] || exit 0
[ -f "$WT_PATH/package.json" ] || exit 0
[ -d "$WT_PATH/node_modules" ] && exit 0

cd "$WT_PATH" || exit 0

if [ -f pnpm-lock.yaml ]; then
  echo "worktree-deps: pnpm install (frozen)..." >&2
  pnpm install --frozen-lockfile >&2 2>&1
elif [ -f yarn.lock ]; then
  echo "worktree-deps: yarn install (frozen)..." >&2
  yarn install --frozen-lockfile >&2 2>&1
elif [ -f bun.lockb ] || [ -f bun.lock ]; then
  echo "worktree-deps: bun install (frozen)..." >&2
  bun install --frozen-lockfile >&2 2>&1
elif [ -f package-lock.json ]; then
  echo "worktree-deps: npm ci..." >&2
  npm ci >&2 2>&1
fi

# Never block worktree entry on install failure
exit 0
