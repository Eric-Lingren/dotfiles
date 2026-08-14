#!/usr/bin/env bash
# Run all characterization tests for the egress adapter consolidation.
# Usage: bash run-all.sh
# Exit 0 = all suites passed. Exit 1 = one or more suites failed.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

run_suite() {
  local script="$1"
  local env_overrides="${2:-}"
  echo ""
  echo ">>> Running: $(basename "$script")"
  if env $env_overrides bash "$script"; then
    echo "<<< SUITE PASSED"
  else
    echo "<<< SUITE FAILED"
    FAILURES=$((FAILURES + 1))
  fi
}

run_suite "$DIR/test-gh-adapter.sh"
run_suite "$DIR/test-notion-adapter.sh"
run_suite "$DIR/test-linear-adapter.sh"

echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "=== ALL SUITES PASSED ==="
  exit 0
else
  echo "=== $FAILURES SUITE(S) FAILED ==="
  exit 1
fi
