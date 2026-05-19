#!/bin/bash
# List spike/*, feat/*, and fix/* branches with last commit info and PRD status.

branches=$(git branch --list "spike/*" "feat/*" "fix/*" 2>/dev/null | sed 's/^[* ]*//')

if [ -z "$branches" ]; then
  echo "No spike, feat, or fix branches in this repo."
  exit 0
fi

printf "%-40s %-12s %-40s %s\n" "Branch" "Date" "Last commit" "PRD"
printf "%-40s %-12s %-40s %s\n" "------" "----" "-----------" "---"

while IFS= read -r branch; do
  date=$(git log -1 --format="%as" "$branch" 2>/dev/null)
  msg=$(git log -1 --format="%s" "$branch" 2>/dev/null)
  # Truncate message to 40 chars
  msg="${msg:0:40}"

  prd="no"
  if git ls-tree "$branch" docs/prd/ >/dev/null 2>&1; then
    prd="yes"
  elif git ls-tree "$branch" client/docs/prd/ >/dev/null 2>&1; then
    prd="yes"
  fi

  printf "%-40s %-12s %-40s %s\n" "$branch" "$date" "$msg" "$prd"
done <<< "$branches"
