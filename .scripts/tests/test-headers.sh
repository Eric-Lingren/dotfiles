#!/usr/bin/env bash
# test-headers.sh — Validate that all target .scripts/ files have the required 3-line header
# What: checks each target file for lines matching # <name> — <one-liner>, # What:, and # When: within the first 4 lines
# When: run to verify T-0076 acceptance criteria; exit 0 = all pass, non-zero = failures present

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

check_header() {
  local file="$1"
  local path="$SCRIPTS_DIR/$file"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: $file — file not found at $path"
    FAIL=$((FAIL + 1))
    return
  fi

  # Read first 4 lines
  local line1 line2 line3 line4
  line1=$(sed -n '1p' "$path")
  line2=$(sed -n '2p' "$path")
  line3=$(sed -n '3p' "$path")
  line4=$(sed -n '4p' "$path")

  local errors=()

  # Determine if file has a shebang
  if [[ "$line1" == '#!'* ]]; then
    # Header should be on lines 2-4
    if ! echo "$line2" | grep -qE '^# .+ — .+'; then
      errors+=("line 2 does not match '# <name> — <one-liner>' pattern (got: $line2)")
    fi
    if ! echo "$line3" | grep -qE '^# What:'; then
      errors+=("line 3 does not start with '# What:' (got: $line3)")
    fi
    if ! echo "$line4" | grep -qE '^# When:'; then
      errors+=("line 4 does not start with '# When:' (got: $line4)")
    fi
  else
    # No shebang — header should be on lines 1-3
    if ! echo "$line1" | grep -qE '^# .+ — .+'; then
      errors+=("line 1 does not match '# <name> — <one-liner>' pattern (got: $line1)")
    fi
    if ! echo "$line2" | grep -qE '^# What:'; then
      errors+=("line 2 does not start with '# What:' (got: $line2)")
    fi
    if ! echo "$line3" | grep -qE '^# When:'; then
      errors+=("line 3 does not start with '# When:' (got: $line3)")
    fi
  fi

  if [[ ${#errors[@]} -eq 0 ]]; then
    echo "PASS: $file"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $file"
    for err in "${errors[@]}"; do
      echo "  - $err"
    done
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-headers.sh: 3-line header validation ==="
echo ""

check_header "gxcheck"
check_header "gxclean"
check_header "gxmove"
check_header "gxpush"
check_header "gxsync"
check_header "gx-lib.sh"
check_header "pr-commit"
check_header "pr-desc"
check_header "gxpush-issue-link.test.sh"

echo ""
echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
