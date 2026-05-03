#!/bin/bash
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
