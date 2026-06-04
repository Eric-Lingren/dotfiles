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

# Guard against the old 2-arg API: validate-schema.sh <schema-path> <instance-path>
# The new API validates schema files against their embedded examples — passing an
# instance file as the second arg silently passes (no examples[]) instead of checking it.
if [[ $# -eq 2 && -f "$1" ]]; then
    echo "ERROR: validate-schema.sh API changed." >&2
    echo "  Old form: validate-schema.sh <schema-path> <instance-path>" >&2
    echo "  New form: validate-schema.sh [--self-test] [schema-file...]" >&2
    echo "  To validate schema files and their embedded examples, pass just the schema file(s)." >&2
    exit 1
fi

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
