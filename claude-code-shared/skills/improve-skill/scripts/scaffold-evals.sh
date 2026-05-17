#!/usr/bin/env bash
# scaffold-evals.sh - Create or reset the evals directory for a skill
#
# Usage: scaffold-evals.sh <skill-dir> [--reset]

set -euo pipefail

SKILL_DIR="${1:?Usage: scaffold-evals.sh <skill-dir> [--reset]}"
RESET="${2:-}"

EVALS_DIR="$SKILL_DIR/evals"

if [[ "$RESET" == "--reset" ]] && [[ -d "$EVALS_DIR" ]]; then
  rm -rf "$EVALS_DIR"
  echo "Deleted $EVALS_DIR"
fi

if [[ ! -d "$EVALS_DIR" ]]; then
  mkdir -p "$EVALS_DIR"
  echo "Created $EVALS_DIR"
fi

# Check which files exist
for f in eval.json learnings.md scores.json; do
  if [[ -f "$EVALS_DIR/$f" ]]; then
    echo "EXISTS: $EVALS_DIR/$f"
  else
    echo "MISSING: $EVALS_DIR/$f"
  fi
done

# Initialize scores.json if missing
if [[ ! -f "$EVALS_DIR/scores.json" ]]; then
  echo '{"runs": []}' > "$EVALS_DIR/scores.json"
  echo "Initialized $EVALS_DIR/scores.json"
fi

# Count tokens in SKILL.md (rough estimate: wc -w * 1.3)
if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
  WORDS=$(wc -w < "$SKILL_DIR/SKILL.md")
  TOKENS=$(echo "$WORDS * 1.3" | bc | cut -d. -f1)
  echo "SKILL.md: ~${WORDS} words, ~${TOKENS} tokens"
fi
