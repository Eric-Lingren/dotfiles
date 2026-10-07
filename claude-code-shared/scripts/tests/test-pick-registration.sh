#!/usr/bin/env bash
# Smoke test: /pick and pick-scorer registration chain.
# Usage: bash test-pick-registration.sh   (exit 0 = all pass)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SHARED="$(cd "$HERE/../.." && pwd)"
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = true ]; then ok "$1"; else bad "$1"; fi; }
py() { python3 -c "$1" "$SHARED" >/dev/null 2>&1 && echo true || echo false; }

echo "=== pick registration smoke test ==="

check "model-tiers: skills.pick is T1" "$(py 'import json,sys;d=json.load(open(sys.argv[1]+"/resources/model-tiers.json"));assert d["skills"]["pick"]=="T1"')"
check "model-tiers: agents.pick-scorer set" "$(py 'import json,sys;d=json.load(open(sys.argv[1]+"/resources/model-tiers.json"));assert d["agents"]["pick-scorer"] in d["tiers"]')"
check "SKILL.md frontmatter matches T1 tier (haiku/low)" "$(py '
import json,re,sys
r=sys.argv[1]
t=json.load(open(r+"/resources/model-tiers.json"));tier=t["tiers"][t["skills"]["pick"]]
fm=open(r+"/skills/pick/SKILL.md").read().split("---")[1]
assert re.search(r"^model: "+tier["model"]+"$",fm,re.M) and re.search(r"^effort: "+tier["effort"]+"$",fm,re.M)')"
check "SKILL.md has disable-model-invocation: true" "$(grep -q '^disable-model-invocation: true$' "$SHARED/skills/pick/SKILL.md" && echo true || echo false)"
check "registry.json: pick-scorer entry, file exists, consumer pick" "$(py '
import json,os,sys
r=sys.argv[1]
reg=json.load(open(r+"/agents/registry.json"))
reg=reg["agents"] if isinstance(reg,dict) else reg
e=[x for x in reg if x["name"]=="pick-scorer"][0]
assert os.path.isfile(r+"/"+e["file"]) and "pick" in e["consumers"]')"
check "pipeline edge pick -> grill-me (target dir exists)" "$(py '
import json,os,sys
r=sys.argv[1]
n=json.load(open(r+"/skill-pipeline.json"))["skills"]["pick"]["next"]
assert [e["skill"] for e in n]==["grill-me"]
assert all(os.path.isdir(r+"/skills/"+e["skill"]) for e in n)')"
check "pick tail block bakes /grill-me suggestion" "$(sed -n '/learning-capture:start/,/learning-capture:end/p' "$SHARED/skills/pick/SKILL.md" | grep -q '/grill-me' && echo true || echo false)"
inj=$(python3 "$SHARED/scripts/learning/inject-learning-tail.py" --check --skills-dir "$SHARED/skills" --pipeline "$SHARED/skill-pipeline.json" 2>&1); injrc=$?
check "injector validates pipeline slugs (rc 0, none missing)" "$([ $injrc -eq 0 ] && echo "$inj" | grep -q 'missing: 0' && echo true || echo false)"
check "injector reports pick tail up to date" "$(echo "$inj" | grep -E '^ +ok +pick$' >/dev/null && echo true || echo false)"
check "learning-contract lists skills/pick/" "$(grep -q '^- `skills/pick/`' "$SHARED/contracts/learning-contract.md" && echo true || echo false)"
check "benchmark CMD set includes pick" "$(grep -q '"find-work", "pick"' "$SHARED/scripts/usage/cc-usage-benchmark.py" && echo true || echo false)"
check "repo-policy: non-empty pick_buckets for github and linear repos" "$(py '
import json,sys
d=json.load(open(sys.argv[1]+"/resources/repo-policy.json"))
def walk(o):
    if isinstance(o,dict):
        if "pick_buckets" in o: yield o
        for v in o.values(): yield from walk(v)
    elif isinstance(o,list):
        for v in o: yield from walk(v)
rs=list(walk(d))
assert {"github","linear"}<={r.get("issue_tracker") for r in rs}
assert all(r["pick_buckets"] for r in rs)')"
check "sync-model-tiers --check clean" "$(python3 "$SHARED/scripts/registration/sync-model-tiers.py" --check 2>&1 | grep -q 'would change: 0' && echo true || echo false)"

echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
