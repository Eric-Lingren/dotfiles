#!/usr/bin/env bash
# Usage: doc-filename.sh <slug> <ext>
# Outputs: YYYYMMDD-HHMM-{slug}.{ext}
# Single source of truth for dated doc filename formatting across all skills.
set -euo pipefail

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "Usage: doc-filename.sh <slug> <ext>" >&2
  exit 1
fi

echo "$(date +%Y%m%d-%H%M)-${1}.${2}"
