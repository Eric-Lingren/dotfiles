#!/usr/bin/env bash
# Smoke tests for /pick blocker tiers. Fixture-based; no real gh/Linear calls.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SHARED="$(cd "$HERE/../.." && pwd)"
P="$SHARED/scripts/pick"
F="$HERE/fixtures/pick-blockers"
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = true ]; then ok "$1"; else bad "$1"; fi; }
R=Eric-Lingren/SpawnedSapien
echo "=== pick blockers smoke test ==="

export PICK_GH_PRS="$(cat "$F/gh-prs.json")"
export PICK_GH_ISSUES='{"#310":"open","#320":"open"}'

# Native dependencies
native=$(GH_ISSUE_LIST_FIXTURE="$F/gh-issues.json" bash "$P/pick-fetch-gh.sh" $R polish \
  | PICK_GH_DEPS="$(cat "$F/gh-deps.json")" python3 "$P/blockers.py" resolve)
rn=$(printf '%s' "$native" | python3 "$P/rank-render.py")
# Body-text fallback (no native deps)
body=$(GH_ISSUE_LIST_FIXTURE="$F/gh-issues-body.json" bash "$P/pick-fetch-gh.sh" $R polish \
  | PICK_GH_DEPS='{}' python3 "$P/blockers.py" resolve)
rb=$(printf '%s' "$body" | python3 "$P/rank-render.py")

check "ready #301 ranks first" "$(printf '%s' "$rn" | grep -E '^1\. ' | grep -q '#301' && echo true || echo false)"
check "stackable #302 ranks second" "$(printf '%s' "$rn" | grep -E '^2\. ' | grep -q '#302' && echo true || echo false)"
check "blocked #303 hidden, count shown" "$(printf '%s' "$rn" | grep -q '#303' && echo false || { printf '%s' "$rn" | grep -q '1 blocked hidden' && echo true || echo false; })"
check "stackable start line: wt <branch> <base>, no --base" \
  "$(printf '%s' "$rn" | grep -q 'start: wt stackable-thing-302 feat/blocker-310  ->  /grill-me #302' && ! printf '%s' "$rn" | grep -q -- '--base' && echo true || echo false)"
check "ready start line has no base" "$(printf '%s' "$rn" | grep -q 'start: wt ready-thing-301  ->' && echo true || echo false)"
check "body-text fallback classifies the same as native" "$([ "$rn" = "$rb" ] && echo true || echo false)"

# merged blocker counts as ready
m=$(printf '%s' "$native" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for c in d["candidates"]:
    for b in c["blockers"]: b["state"]="merged"
print(json.dumps(d))' | python3 "$P/rank-render.py")
check "all blockers merged: all three ready, none hidden" "$(printf '%s' "$m" | grep -q 'blocked hidden' && echo false || { [ "$(printf '%s' "$m" | grep -c 'start: wt')" = 3 ] && echo true || echo false; })"

# Linear shape: blocker In Review with PR and branch is stackable
lin=$(python3 - <<'PY'
import json
mk=lambda i,bl:{"id":i,"source":"linear","repo":"r","title":i,"url":"u","labels":[],"assignees":[],"points":1,"state":"Backlog","parent":None,"project":None,"blockers":bl,"branch":"br-"+i,"created_at":"2026-09-01T00:00:00Z"}
print(json.dumps({"repo":"r","bucket":"unclaimed","sort":["hide-blocked","smallest"],"candidates":[
 mk("K-1",[{"id":"K-9","state":"In Review","pr_in_review":True,"branch":"eric/k-9"}]),
 mk("K-2",[{"id":"K-8","state":"In Progress","pr_in_review":False,"branch":"eric/k-8"}]),
 mk("K-3",[])]}))
PY
)
rl=$(printf '%s' "$lin" | python3 "$P/rank-render.py")
check "linear: ready first, stackable with base, blocked hidden" "$(printf '%s' "$rl" | grep -E '^1\. ' | grep -q K-3 && printf '%s' "$rl" | grep -q 'start: wt br-K-1 eric/k-9' && printf '%s' "$rl" | grep -q '1 blocked hidden' && ! printf '%s' "$rl" | grep -q K-2 && echo true || echo false)"

python3 -c "
import json
b=json.load(open('$SHARED/resources/repo-policy.json'))
ss=b['$R']['pick_buckets']; q=b['Quaestor-Technologies/Quaestor-Web']['pick_buckets']
assert all('hide-blocked' in v['sort'] for v in list(ss.values())+list(q.values()))" \
  && ok "hide-blocked on all SpawnedSapien and Quaestor-Web buckets" || bad "hide-blocked on all buckets"

echo "passed=$PASS failed=$FAIL"
[ $FAIL -eq 0 ]
