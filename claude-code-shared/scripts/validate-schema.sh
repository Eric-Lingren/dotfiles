#!/usr/bin/env bash
# validate-schema.sh — validate JSON schema files and their embedded examples.
#
# Usage:
#   validate-schema.sh [--self-test] [schema-file ...]
#
# Validates the examples[] of each schema file against itself, with
# cross-file $ref resolution across all contracts/*.json files.
#
# Options:
#   --self-test    Run the built-in cross-file $ref mechanism self-test
#   (no args)      Validate all contracts/*.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$(cd "${SCRIPT_DIR}/../contracts" && pwd)"
PY_SCRIPT="${SCRIPT_DIR}/validate-schema.py"

if [[ ! -f "${PY_SCRIPT}" ]]; then
    echo "ERROR: ${PY_SCRIPT} not found" >&2
    exit 1
fi

if ! python3 -c "import jsonschema" 2>/dev/null; then
    echo "ERROR: jsonschema not installed. Run: pip install 'jsonschema[format]'" >&2
    exit 1
fi

exec python3 "${PY_SCRIPT}" "${CONTRACTS_DIR}" "$@"
