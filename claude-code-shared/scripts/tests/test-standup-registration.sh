#!/usr/bin/env bash
# Verifies that the standup skill is fully registered in all three infra config files.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"

PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

check() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "true" ]; then
    assert_pass "$desc"
  else
    assert_fail "$desc"
  fi
}

echo "=== standup registration test ==="

MODEL_TIERS="$SHARED_DIR/resources/model-tiers.json"
REPO_POLICY="$SHARED_DIR/resources/repo-policy.json"
CLEAN_SKILL="$SHARED_DIR/skills/clean-scaffolding/SKILL.md"

# AC1: model-tiers.json contains a standup skill entry
has_standup=$(python3 - <<PYEOF
import json
cfg = json.load(open('$MODEL_TIERS'))
print('true' if 'standup' in cfg.get('skills', {}) else 'false')
PYEOF
)
check "model-tiers.json contains standup in skills map" "$has_standup"

# Also verify the tier is T2
standup_tier=$(python3 - <<PYEOF
import json
cfg = json.load(open('$MODEL_TIERS'))
print(cfg.get('skills', {}).get('standup', ''))
PYEOF
)
check "model-tiers.json standup tier is T2" "$([ "$standup_tier" = "T2" ] && echo true || echo false)"

# AC2: repo-policy.json contains docs/standups/ in the Quaestor-Web exclude list
has_standups_exclude=$(python3 - <<PYEOF
import json
policy = json.load(open('$REPO_POLICY'))
qw_exclude = policy.get('Quaestor-Technologies/Quaestor-Web', {}).get('exclude', [])
print('true' if 'docs/standups/' in qw_exclude else 'false')
PYEOF
)
check "repo-policy.json Quaestor-Web exclude list contains docs/standups/" "$has_standups_exclude"

# AC3: clean-scaffolding SKILL.md Untouched list contains docs/standups/
has_untouched=$(grep -c "docs/standups/" "$CLEAN_SKILL" 2>/dev/null || echo 0)
check "clean-scaffolding SKILL.md Untouched list contains docs/standups/" "$([ "$has_untouched" -ge 1 ] && echo true || echo false)"

echo ""
echo "Results: $PASS passed, $FAIL failed."
[ "$FAIL" -eq 0 ]
