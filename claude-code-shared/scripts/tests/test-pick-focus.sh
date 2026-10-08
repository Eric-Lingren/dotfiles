#!/usr/bin/env bash
# Smoke tests for /pick focus menu (shared-pool buckets). Fixture-based; read-only.
# Usage: bash test-pick-focus.sh   (exit 0 = all pass)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SHARED="$(cd "$HERE/../.." && pwd)"
P="$SHARED/scripts/pick"
FX="$HERE/fixtures/pick-focus"
QW=Quaestor-Technologies/Quaestor-Web
PASS=0; FAIL=0
check() { if [ "$2" = true ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; FAIL=$((FAIL+1)); fi; }
eq() { [ "$1" = "$2" ] && echo true || echo false; }

echo "=== pick focus smoke test ==="

o=$(LINEAR_ISSUES_FIXTURE="$FX/sprint.json" bash "$P/focus-options.sh" $QW unclaimed)
v=$(printf '%s' "$o" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["ask"],",".join(d["options"]))')
check "unclaimed asks; options = sprint projects + No focus" "$(eq "$v" "True Billing,Exports,No focus")"

o=$(LINEAR_ISSUES_FIXTURE="$FX/sprint.json" bash "$P/focus-options.sh" $QW my-sprint)
check "my-sprint never prompts" "$(eq "$o" '{"ask": false, "options": []}')"

for b in $(python3 -c 'import json;print(" ".join(json.load(open("'"$SHARED"'/resources/repo-policy.json"))["Eric-Lingren/SpawnedSapien"]["pick_buckets"]))'); do
  o=$(bash "$P/focus-options.sh" Eric-Lingren/SpawnedSapien "$b")
  check "SpawnedSapien/$b never prompts" "$(eq "$o" '{"ask": false, "options": []}')"
done

pool=$(mktemp)
LINEAR_ISSUES_FIXTURE="$FX/pool.json" bash "$P/pick-fetch-linear.sh" $QW unclaimed > "$pool"
ids() { grep -oE '^[0-9]+\. KEY-[0-9]+' | sed -E 's/^[0-9]+\. //' | paste -sd, -; }
base=$(python3 "$P/rank-render.py" "$pool" | ids)
check "baseline order (smallest first)" "$(eq "$base" "KEY-10,KEY-11,KEY-12")"
foc=$(python3 "$P/rank-render.py" "$pool" --focus Billing | ids)
check "focus Billing moves KEY-12 up, keeps all 3" "$(eq "$foc" "KEY-12,KEY-10,KEY-11")"
hdr=$(python3 "$P/rank-render.py" "$pool" --focus Billing | grep -c '^Focus: Billing$')
check "header shows active focus" "$(eq "$hdr" 1)"
nf=$(python3 "$P/rank-render.py" "$pool" --focus "No focus")
check "No focus: unchanged order, no Focus header" "$(eq "$(printf '%s' "$nf" | ids)|$(printf '%s' "$nf" | grep -c '^Focus:')" "KEY-10,KEY-11,KEY-12|0")"
si=$(python3 "$P/rank-render.py" "$pool" --scorer-input --focus Billing | python3 -c 'import json,sys;print(json.load(sys.stdin)["candidates"][0]["id"])')
check "scorer-input honors focus" "$(eq "$si" KEY-12)"

before=$(find "$HERE/fixtures" "$P" -type f | wc -l)
LINEAR_ISSUES_FIXTURE="$FX/sprint.json" bash "$P/focus-options.sh" $QW unclaimed >/dev/null
after=$(find "$HERE/fixtures" "$P" -type f | wc -l)
check "no files written to disk" "$(eq "$before" "$after")"

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
