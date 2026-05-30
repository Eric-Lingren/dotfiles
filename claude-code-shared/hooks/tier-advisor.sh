#!/bin/bash
# UserPromptSubmit hook: advisory model-tier nudge (both directions).
#
# Session default is Sonnet/xhigh (T3). This hook suggests:
#   - UPGRADE to Opus (T4) when a prompt smells like deep reasoning.
#   - DOWNGRADE to Haiku (T1) when a prompt is a pure cheap lookup.
#
# Hooks CANNOT set the model for the current turn (off-by-one timing), so this
# never switches models. It emits a one-line advisory the assistant can act on.
#
# Conservative on purpose. Tune the patterns below. Disable entirely with:
#   export CLAUDE_TIER_ADVISOR=0
#
# Exits 0 always (advisory, never blocks). Stdout becomes context for the turn.

[ "${CLAUDE_TIER_ADVISOR:-1}" = "0" ] && exit 0

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Skill invocations self-tier via frontmatter; skip them.
echo "$PROMPT" | grep -q "<command-name>" && exit 0

# ---- UPGRADE (T4 / Opus): strong deep-reasoning signals only ----
T4_PATTERN="architect|architecture|system design|design (the|a) (system|schema|data model|api)\
|trade-?off|migration strategy|rearchitect|redesign\
|race condition|deadlock|memory leak|concurrency|complex ?debug|hard bug|why is .* (failing|broken)\
|think (this|it) through|reason through|long.term (viability|strategy)|holistic|end.to.end design"

T4_MATCH=$(echo "$PROMPT" | grep -ioE "$T4_PATTERN" | head -1)
if [ -n "$T4_MATCH" ]; then
  echo "[tier-advisor] Deep-reasoning signal (\"$T4_MATCH\"). Default is Sonnet (T3). If this is genuinely T4 work, suggest the user run \`/model opus\` (xhigh). Do not mention this note otherwise."
  exit 0
fi

# ---- DOWNGRADE (T1 / Haiku): pure lookups, only when no action verb present ----
# Action verbs mean real work, not a lookup -> never downgrade.
ACTION="fix|chang|add|implement|refactor|build|writ|updat|edit|creat|delet|remov|renam|migrat|design|debug|review|test|optimiz|wire|install|configur|set up|generat|run "
echo "$PROMPT" | grep -ioqE "$ACTION" && exit 0

# Pure-lookup openers.
T1_PATTERN="^(where (is|are)|what (is|does|are)|how (do i|to)|find (the|all)|list (the|all)|show me|search for|grep |look (up|for)|which file|locate|status (of|on))\b"
T1_MATCH=$(echo "$PROMPT" | grep -ioE "$T1_PATTERN" | head -1)
if [ -n "$T1_MATCH" ]; then
  echo "[tier-advisor] Looks like a pure lookup (\"$T1_MATCH\"). To save cost, suggest the user run \`/model haiku\` (low) for this. Do not mention this note otherwise."
  exit 0
fi

exit 0
