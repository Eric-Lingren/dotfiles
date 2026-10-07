#!/usr/bin/env bash
ORG="your-org"
USERS=("eric-lingren" "naomiflagg" "katherineberton" "rileybutterfield" "jmunowitch")
QUARTERS=("Q1:2026-01-01..2026-03-31" "Q2:2026-04-01..2026-06-30" "Q3:2026-07-01..2026-09-30")

count() { gh search prs "$@" --owner "$ORG" --limit 1000 --json number --jq length; }

# Percent change from $1 (previous) to $2 (current)
pct() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    if (a == "" || a == 0) print "n/a";
    else printf "%+.1f%%", (b - a) / a * 100
  }'
}

echo "user,quarter,opened,opened_qoq,merged,merged_qoq,reviewed,reviewed_qoq,commented,commented_qoq"
for u in "${USERS[@]}"; do
  p_opened=""; p_merged=""; p_reviewed=""; p_commented=""
  for q in "${QUARTERS[@]}"; do
    name="${q%%:*}"; range="${q#*:}"

    opened=$(count --author "$u" --created "$range")
    merged=$(count --author "$u" --merged-at "$range")
    reviewed=$(count --reviewed-by "$u" --created "$range" -- "-author:$u")
    commented=$(count --commenter "$u" --created "$range" -- "-author:$u")

    echo "$u,$name,$opened,$(pct "$p_opened" "$opened"),$merged,$(pct "$p_merged" "$merged"),$reviewed,$(pct "$p_reviewed" "$reviewed"),$commented,$(pct "$p_commented" "$commented")"

    p_opened=$opened; p_merged=$merged; p_reviewed=$reviewed; p_commented=$commented
    sleep 8  # search API is rate limited to ~30 requests/min
  done
done