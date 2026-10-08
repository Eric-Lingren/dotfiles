#!/usr/bin/env bash
# Smoke tests for /pick teammate overlap. Fixture-based; no Linear calls.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "$HERE/../.." && pwd)/scripts/pick"
FIX="$HERE/fixtures/pick"
PASS=0; FAIL=0
check() { if [ "$2" = true ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; FAIL=$((FAIL+1)); fi; }
T="$(mktemp -d)"

LINEAR_ACTIVITY_FIXTURE="$FIX/overlap-activity.json" bash "$P/pick-fetch-linear-activity.sh" > "$T/act.json"
n=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$T/act.json")
check "activity fetch normalizes 2 entries" "$([ "$n" = 2 ] && echo true || echo false)"

python3 "$P/overlap.py" "$FIX/overlap-cands.json" "$T/act.json" > "$T/out.json"
ids=$(python3 -c 'import json,sys;print(",".join(c["id"] for c in json.load(open(sys.argv[1]))["candidates"]))' "$T/out.json")
check "teammate sibling under same parent excludes ticket" "$([ "$ids" = "KEY-102,KEY-103" ] && echo true || echo false)"
note=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["candidates"][0]["notes"][0])' "$T/out.json")
check "project overlap adds annotation" "$([ "$note" = "👥 Pat Peer active in Sync" ] && echo true || echo false)"

with=$(python3 "$P/rank-render.py" "$FIX/overlap-cands.json" --activity "$T/act.json" | grep -o '^[0-9]*\. KEY-10[0-9]' | grep -o 'KEY-10[0-9]' | tr '\n' ,)
check "rank order of kept tickets unchanged" "$([ "$with" = "KEY-102,KEY-103," ] && echo true || echo false)"
python3 "$P/rank-render.py" "$FIX/overlap-cands.json" --activity "$T/act.json" | grep -q "👥 Pat Peer active in Sync"
check "render shows annotation" "$([ $? -eq 0 ] && echo true || echo false)"

echo "passed=$PASS failed=$FAIL"; [ "$FAIL" -eq 0 ]
