#!/bin/bash
LOCKFILE="/tmp/cmux-startup.lock"
if [ -f "$LOCKFILE" ]; then
  if [ $(( $(date +%s) - $(stat -f %m "$LOCKFILE") )) -lt 60 ]; then
    exit 0
  fi
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT


# Retry identify
for i in $(seq 1 10); do
  WS=$(cmux identify 2>/dev/null | grep workspace_ref | head -1 | grep -o 'workspace:[0-9]*')
  [ -n "$WS" ] && break
  sleep 0.5
done
[ -z "$WS" ] && { echo "ERROR: Could not identify workspace" >&2; exit 1; }

# Get the initial surface
S1=$(cmux tree --workspace "$WS" | grep 'surface ' | head -1 | grep -o 'surface:[0-9]*')
[ -z "$S1" ] && { echo "ERROR: No initial surface found" >&2; exit 1; }

# Set Workspace Name
cmux rename-workspace --workspace "$WS" "Quaestor Dev Env"

# Left (full height): Dev
cmux rename-tab --surface "$S1" "Dev"
cmux send --surface "$S1" "source ~/.zshrc && cd ~/Documents/dev/Quaestor-Web && dev start"
cmux send-key --surface "$S1" Return
