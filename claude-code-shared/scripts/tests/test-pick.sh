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
