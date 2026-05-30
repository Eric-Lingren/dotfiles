#!/bin/bash
# Weekly Claude Code usage report. Runs the benchmark across BOTH profiles
# (cco + cch) and writes a timestamped report. Designed to run via launchd
# (see launchd/com.ericlingren.cc-usage-report.plist), but is safe to run by hand.
#
# Output dir override: CC_USAGE_REPORT_DIR (default ~/.cache/cc-usage-reports)
set -uo pipefail

PY=/usr/bin/python3
SCRIPT="$HOME/.dotfiles/claude-code-shared/scripts/cc-usage-benchmark.py"
OUTDIR="${CC_USAGE_REPORT_DIR:-$HOME/.cache/cc-usage-reports}"
mkdir -p "$OUTDIR"

STAMP=$(date +%Y-%m-%d)
OUT="$OUTDIR/usage-$STAMP.txt"

{
  echo "Claude Code usage report — $STAMP"
  echo "================================================================"
  echo
  "$PY" "$SCRIPT"
  echo
  echo "================================================================"
  echo "WEEKLY TREND"
  echo "================================================================"
  "$PY" "$SCRIPT" --trend
  echo
  echo "================================================================"
  echo "TIER ADHERENCE"
  echo "================================================================"
  "$PY" "$SCRIPT" --adherence
} > "$OUT" 2>&1

echo "wrote $OUT"
