#!/usr/bin/env bash
# Extract embedded JSON from an HTML PRD file.
# Usage: extract-prd-json.sh <path-to-prd.html>
# If the file is .md, cats it as-is (no JSON to extract).
# If the file is .html, extracts the <script id="prd-data"> block.

set -euo pipefail

file="${1:?Usage: extract-prd-json.sh <prd-file>}"

if [[ ! -f "$file" ]]; then
  echo "Error: file not found: $file" >&2
  exit 1
fi

case "$file" in
  *.html)
    sed -n '/<script type="application\/json" id="prd-data">/,/<\/script>/{
      /<script/d
      /<\/script>/d
      p
    }' "$file"
    ;;
  *.md)
    cat "$file"
    ;;
  *)
    echo "Error: unsupported file type: $file" >&2
    exit 1
    ;;
esac
