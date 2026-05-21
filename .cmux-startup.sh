#!/bin/bash
LOCKFILE="/tmp/cmux-startup.lock"
if [ -f "$LOCKFILE" ]; then
  if [ $(( $(date +%s) - $(stat -f %m "$LOCKFILE") )) -lt 60 ]; then
    exit 0
  fi
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

wait_for_surface() {
  local id="$1"
  local i=0
  while [ $i -lt 20 ]; do
    cmux tree --workspace "$WS" 2>/dev/null | grep -q "$id" && return 0
    sleep 0.3
    i=$((i + 1))
  done
  echo "ERROR: Timed out waiting for $id" >&2; return 1
}

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

# Top-right: Storybook (split right from Dev)
S2=$(cmux new-split right --surface "$S1" --workspace "$WS" | grep -o 'surface:[0-9]*' | head -1)
[ -z "$S2" ] && { echo "ERROR: S2 split failed" >&2; exit 1; }
wait_for_surface "$S2"
cmux rename-tab --surface "$S2" "Storybook"
cmux send --surface "$S2" "source ~/.zshrc && cd ~/Documents/dev/Quaestor-Web/client && yarn storybook"
cmux send-key --surface "$S2" Return

# Bottom-right: Celery (split down from Storybook)
S3=$(cmux new-split down --surface "$S2" --workspace "$WS" | grep -o 'surface:[0-9]*' | head -1)
[ -z "$S3" ] && { echo "ERROR: S3 split failed" >&2; exit 1; }
wait_for_surface "$S3"
cmux rename-tab --surface "$S3" "Celery"
cmux send --surface "$S3" "source ~/.zshrc && cd ~/Documents/dev/Quaestor-Web/app && runcelery"
cmux send-key --surface "$S3" Return
