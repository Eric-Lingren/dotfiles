#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

if echo "$COMMAND" | grep -qE '\bsed\b.*-[a-zA-Z]*i\b'; then
  echo "Destructive sed -i is blocked. Use the Edit tool to make in-place file changes instead." >&2
  exit 2
fi

exit 0
