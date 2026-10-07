#!/usr/bin/env bash
# Smoke tests for /pick (GitHub path). Fixture-based; no real gh/Linear calls.
# Usage: bash test-pick.sh   (exit 0 = all pass)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SHARED="$(cd "$HERE/../.." && pwd)"
P="$SHARED/scripts/pick"
FIX="$HERE/fixtures/pick/gh-issue-list.json"
POLICY="$SHARED/resources/repo-policy.json"
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = true ]; then ok "$1"; else bad "$1"; fi; }

echo "=== pick smoke test ==="

out=$(PICK_REPO=Eric-Lingren/dotfiles bash "$P/resolve-repo.sh"); rc=$?
check "no issue_tracker: clean exit 0" "$([ $rc -eq 0 ] && echo true || echo false)"
check "no issue_tracker: message" "$([ "$out" = "no issue_tracker configured for Eric-Lingren/dotfiles" ] && echo true || echo false)"

out=$(PICK_REPO=Eric-Lingren/SpawnedSapien bash "$P/resolve-repo.sh")
n=$(printf '%s' "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d["buckets"]), d["issue_tracker"])')
check "SpawnedSapien resolves 4 buckets, github" "$([ "$n" = "4 github" ] && echo true || echo false)"

json=$(GH_ISSUE_LIST_FIXTURE="$FIX" bash "$P/pick-fetch-gh.sh" Eric-Lingren/SpawnedSapien pre-launch)
printf '%s' "$json" | python3 "$P/validate-candidates.py"
check "fetch emits JSON that validates" "$([ $? -eq 0 ] && echo true || echo false)"
chk=$(printf '%s' "$json" | python3 -c '
import json,sys
d=json.load(sys.stdin); c={x["id"]:x for x in d["candidates"]}
print(len(c), c["#210"]["blockers"][0]["id"], c["#205"]["branch"])')
check "normalized fields (count, blocker parse, branch slug)" "$([ "$chk" = "3 #190 fix-stripe-webhook-retry-loop-pre-205" ] && echo true || echo false)"

printf '{"candidates":[{"id":1}]}' | python3 "$P/validate-candidates.py" 2>/dev/null
check "validator rejects malformed input" "$([ $? -ne 0 ] && echo true || echo false)"

if GH_ISSUE_LIST_FIXTURE="$FIX" bash "$P/pick-fetch-gh.sh" Eric-Lingren/SpawnedSapien nope 2>/dev/null; then bad "unknown bucket should fail"; else ok "unknown bucket fails"; fi

r=$(printf '%s' "$json" | python3 "$P/rank-render.py")
check "render: blocked #210 hidden" "$(printf '%s' "$r" | grep -q '#210' && echo false || echo true)"
check "render: pre-launch+opsec #190 ranks first" "$(printf '%s' "$r" | grep -E '^1\. ' | grep -q '#190' && echo true || echo false)"
check "render: start line" "$(printf '%s' "$r" | grep -q 'start: wt rotate-leaked-service-key-190  ->  /grill-me #190' && echo true || echo false)"

# --- Linear path (fixture) ---
LFIX="$HERE/fixtures/pick/linear-issues.json"
QW=Quaestor-Technologies/Quaestor-Web
out=$(PICK_REPO=$QW bash "$P/resolve-repo.sh")
n=$(printf '%s' "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(",".join(d["buckets"]), d["issue_tracker"])')
check "Quaestor-Web menu is exactly my-sprint,unclaimed (linear)" "$([ "$n" = "my-sprint,unclaimed linear" ] && echo true || echo false)"
python3 -c "
import json
e=json.load(open('$POLICY'))['$QW']
v=e['pick_verified']; b=e['pick_buckets']
assert v['team_key']=='KEY' and v['states']==['Ready to Assign','Backlog']
assert b['unclaimed']['filter']['team']['key']['eq']==v['team_key']
assert b['unclaimed']['filter']['state']['name']['in']==v['states'] and b['unclaimed']['focus'] is True
assert b['my-sprint']['focus'] is False
assert 'cycle' not in ' '.join(b)" \
  && ok "verified team key/state names recorded in buckets" || bad "verified team key/state names recorded in buckets"
ljson=$(LINEAR_ISSUES_FIXTURE="$LFIX" bash "$P/pick-fetch-linear.sh" $QW unclaimed)
printf '%s' "$ljson" | python3 "$P/validate-candidates.py"
check "linear fetch emits JSON that validates" "$([ $? -eq 0 ] && echo true || echo false)"
shape=$(python3 -c "
import json,sys
g=json.loads(sys.argv[1]); l=json.loads(sys.argv[2])
print(sorted(g['candidates'][0])==sorted(k for k in l['candidates'][0] if k!='prs') and sorted(g)==sorted(k for k in l if k!='focus'))" "$json" "$ljson")
check "linear candidate keys identical to gh shape" "$([ "$shape" = True ] && echo true || echo false)"
chk=$(printf '%s' "$ljson" | python3 -c '
import json,sys
c={x["id"]:x for x in json.load(sys.stdin)["candidates"]}
b=c["KEY-103"]["blockers"]
print(c["KEY-101"]["branch"], c["KEY-101"]["points"], c["KEY-101"]["parent"], c["KEY-101"]["project"], c["KEY-102"]["assignees"][0], c["KEY-102"]["prs"][0].rsplit("/",1)[1], len(b), b[0]["id"], b[0]["state"], b[0]["pr_in_review"])')
check "linear normalized fields (branch, points, parent, blockers, PRs)" "$([ "$chk" = "eric/key-101-trim-empty-rows-from-export 2 KEY-90 Exports Eric Lingren 77 1 KEY-100 In Review True" ] && echo true || echo false)"
r=$(printf '%s' "$ljson" | python3 "$P/rank-render.py")
check "linear render: start line uses gitBranchName" "$(printf '%s' "$r" | grep -q 'start: wt eric/key-101-trim-empty-rows-from-export  ->  /grill-me KEY-101' && echo true || echo false)"
check "linear render: blocked KEY-103 hidden" "$(printf '%s' "$r" | grep -q 'KEY-103' && echo false || echo true)"
check "linear render: no 'cycle' wording" "$(printf '%s' "$r" | grep -qi cycle && echo false || echo true)"
if LINEAR_ISSUES_FIXTURE="$LFIX" bash "$P/pick-fetch-linear.sh" $QW nope 2>/dev/null; then bad "linear unknown bucket should fail"; else ok "linear unknown bucket fails"; fi

# pick-scorer (T-0030)
C30="$HERE/fixtures/pick/candidates-30.json"
SOUT="$HERE/fixtures/pick/scorer-output-25.json"
SIN=$(mktemp)
python3 "$P/rank-render.py" "$C30" --scorer-input > "$SIN"
python3 "$P/validate-scorer.py" input "$SIN"
check "scorer input valid and capped at 25 of 30" "$([ $? -eq 0 ] && [ "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["candidates"]))' "$SIN")" = 25 ] && echo true || echo false)"
python3 "$P/validate-scorer.py" output "$SOUT" --input "$SIN"
check "scorer output fixture (25) schema-valid, ids match input" "$([ $? -eq 0 ] && echo true || echo false)"
echo '{"scores":[{"id":"#1","score":11,"reason":"x"}]}' | python3 "$P/validate-scorer.py" output - 2>/dev/null
check "scorer validator rejects out-of-range score" "$([ $? -ne 0 ] && echo true || echo false)"
echo '{"scores":[{"id":"#1","score":3,"reason":"a\nb"}]}' | python3 "$P/validate-scorer.py" output - 2>/dev/null
check "scorer validator rejects multi-line reason" "$([ $? -ne 0 ] && echo true || echo false)"
r=$(python3 "$P/rank-render.py" "$C30" --scores "$SOUT")
check "render: unpointed shown with warning, not excluded" "$(printf '%s' "$r" | grep -E '^1\. #307.*⚠ unpointed' >/dev/null && echo true || echo false)"
check "render: why line per item" "$([ "$(printf '%s' "$r" | grep -c '   why: ')" = 5 ] && echo true || echo false)"
rm -f "$SIN"
python3 -c "
import json
d=json.load(open('$SHARED/agents/registry.json'))['agents']
e=[a for a in d if a['name']=='pick-scorer'][0]
assert e['consumers']==['pick'] and e['model']=='sonnet'
import os; assert os.path.exists('$SHARED/'+e['file']); assert os.path.exists(os.path.dirname('$SHARED/'+e['file'])+'/pick-scorer-contract.json')" \
  && ok "registry lists pick-scorer; contract next to agent" || bad "registry pick-scorer"

# Read-only guarantee: no write verbs in the skill or scripts (this test file excluded).
hits=$(grep -rEn 'gh issue (edit|close|comment|create)|gh api.*-X *(POST|PATCH|PUT|DELETE)|mutation[ {(]' "$P" "$SHARED/skills/pick" || true)
check "no write calls to GitHub/Linear" "$([ -z "$hits" ] && echo true || echo false)"

python3 -c "
import json,sys
sys.exit(0 if 'pick' in json.load(open('$SHARED/resources/model-tiers.json'))['skills'] else 1)" \
  && ok "model-tiers has pick" || bad "model-tiers has pick"
python3 -c "
import json
b=json.load(open('$POLICY'))['Eric-Lingren/SpawnedSapien']['pick_buckets']
assert sorted(b)==['opsec','polish','pre-launch','seed-ready'] and len(b)<=4" \
  && ok "policy pick_buckets: 4 buckets" || bad "policy pick_buckets"
bash "$HERE/test-standup-registration.sh" >/dev/null && ok "standup registration test still passes" || bad "standup registration test"

echo ""; echo "Results: $PASS passed, $FAIL failed."
[ "$FAIL" -eq 0 ]
