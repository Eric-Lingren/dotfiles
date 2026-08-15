#!/usr/bin/env bash
# Validation script for T-0095: Delete /answer skill and scrub references
# Run BEFORE deletion to capture characterization, run AFTER to verify absence.
# Exit code 0 = all checks pass, 1 = failures.

set -euo pipefail

ROOT="/Users/eric/.dotfiles/claude-code-shared"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

echo "=== T-0095 Validation ==="
echo ""

# 1. /answer skill file must NOT exist
if [ -f "$ROOT/skills/answer/SKILL.md" ]; then
  fail "/answer skill file still exists: $ROOT/skills/answer/SKILL.md"
else
  pass "/answer skill file does not exist"
fi

# 2. skill-pipeline.json must have no "answer" key
if jq -e '.skills | has("answer")' "$ROOT/skill-pipeline.json" > /dev/null 2>&1; then
  fail "skill-pipeline.json still has an 'answer' entry"
else
  pass "skill-pipeline.json has no 'answer' entry"
fi

# 3. model-tiers.json must have no "answer" key in .skills
if jq -e '.skills | has("answer")' "$ROOT/resources/model-tiers.json" > /dev/null 2>&1; then
  fail "model-tiers.json still has an 'answer' entry in .skills"
else
  pass "model-tiers.json has no 'answer' entry in .skills"
fi

# 4. dispatch-tasks SKILL.md must have no /answer or "answer" routing entry
if grep -q '"answer"\|/answer' "$ROOT/skills/dispatch-tasks/SKILL.md" 2>/dev/null; then
  fail "dispatch-tasks SKILL.md still contains an /answer reference"
else
  pass "dispatch-tasks SKILL.md has no /answer entry"
fi

# 5. /investigate skill still exists (guard against accidental deletion)
if [ -f "$ROOT/skills/investigate/SKILL.md" ]; then
  pass "/investigate skill file still exists (not accidentally deleted)"
else
  fail "/investigate skill file is MISSING — accidental deletion!"
fi

# 6. skill-pipeline.json is valid JSON
if jq empty "$ROOT/skill-pipeline.json" > /dev/null 2>&1; then
  pass "skill-pipeline.json is valid JSON"
else
  fail "skill-pipeline.json is NOT valid JSON"
fi

# 7. model-tiers.json is valid JSON
if jq empty "$ROOT/resources/model-tiers.json" > /dev/null 2>&1; then
  pass "model-tiers.json is valid JSON"
else
  fail "model-tiers.json is NOT valid JSON"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
