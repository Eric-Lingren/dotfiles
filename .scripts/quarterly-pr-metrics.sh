#!/usr/bin/env bash
ORG="your-org"
USERS=("eric-gh" "naomi-gh" "kat-gh" "riley-gh")
QUARTERS=("Q1:2026-01-01..2026-03-31" "Q2:2026-04-01..2026-06-30" "Q3:2026-07-01..2026-09-30")

count() { gh search prs "$@" --owner "$ORG" --limit 1000 --json number --jq length; }

echo "user,quarter,opened,merged,reviewed,commented"
for u in "${USERS[@]}"; do
  for q in "${QUARTERS[@]}"; do
    name="${q%%:*}"; range="${q#*:}"
    opened=$(count --author "$u" --created "$range")
    merged=$(count --author "$u" --merged-at "$range")
    reviewed=$(count --reviewed-by "$u" --created "$range" -- "-author:$u")
    commented=$(count --commenter "$u" --created "$range" -- "-author:$u")
    echo "$u,$name,$opened,$merged,$reviewed,$commented"
    sleep 8  # search API is rate limited to ~30 requests/min
  done
done