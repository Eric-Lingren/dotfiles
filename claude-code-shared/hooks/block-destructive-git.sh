#!/bin/bash
# PreToolUse hook: blocks destructive git commands.
# Catches: push --force, reset --hard, clean -f, branch -D, checkout ., restore .,
# stash drop/clear, filter-branch, rebase -i.
# Exits 2 to block, 0 to allow.
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

MATCHED=$(echo "$COMMAND" | grep -ioE \
  "git push[[:space:]].*(-f|--force|--force-with-lease)\
|git reset[[:space:]]+--hard\
|git clean[[:space:]]+-[a-z]*f\
|git branch[[:space:]]+-D\
|git checkout[[:space:]]+(\.|--)\
|git restore[[:space:]]+\.\
|git stash[[:space:]]+(drop|clear)\
|git filter-branch\
|git rebase[[:space:]]+-i" \
  | head -1)

if [ -n "$MATCHED" ]; then
  echo "Blocked: destructive git command detected ('$MATCHED')." >&2
  echo "" >&2
  echo "Run manually if intentional:" >&2
  echo "" >&2
  echo "  $COMMAND" >&2
  exit 2
fi

exit 0
