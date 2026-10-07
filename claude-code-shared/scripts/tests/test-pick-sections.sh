#!/usr/bin/env bash
# Smoke tests for /pick free-text bucket mapping and other-repos section.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "$HERE/../.." && pwd)/scripts/pick"
FIX="$HERE/fixtures/pick/sections-8.json"
PASS=0; FAIL=0
check() { if [ "$2" = true ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; FAIL=$((FAIL+1)); fi; }
QW=Quaestor-Technologies/Quaestor-Web

out=$(python3 "$P/map-bucket.py" "quick wins" --repo $QW my-sprint unclaimed)
check "'quick wins' -> unclaimed" "$([ "$out" = unclaimed ] && echo true || echo false)"
out=$(python3 "$P/map-bucket.py" "my sprint" --repo $QW my-sprint unclaimed)
check "'my sprint' -> my-sprint" "$([ "$out" = my-sprint ] && echo true || echo false)"
out=$(python3 "$P/map-bucket.py" "unclaimed" --repo $QW my-sprint unclaimed)
check "exact name" "$([ "$out" = unclaimed ] && echo true || echo false)"
python3 "$P/map-bucket.py" "banana smoothie" --repo $QW my-sprint unclaimed >/dev/null
check "unmatched text exits 1 (menu fallback)" "$([ $? -eq 1 ] && echo true || echo false)"

# fixture: 8 candidates, 4 in another repo
r=$(python3 "$P/rank-render.py" "$FIX")
main=$(printf '%s\n' "$r" | sed '/^other repos/,$d' | grep -cE '^[0-9]+\. ')
oth=$(printf '%s\n' "$r" | sed -n '/^other repos/,$p' | grep -cE '^[0-9]+\. ')
check "main list at most 5 (got $main)" "$([ "$main" = 4 ] && echo true || echo false)"
check "other-repos section at most 3 (got $oth)" "$([ "$oth" = 3 ] && echo true || echo false)"
tagged=$(printf '%s\n' "$r" | sed -n '/^other repos/,$p' | grep -E '^[0-9]+\. ' | grep -c '\[Org/Other\]')
check "other-repos items tagged with repo" "$([ "$tagged" = 3 ] && echo true || echo false)"
echo "pass=$PASS fail=$FAIL"; [ $FAIL -eq 0 ]
