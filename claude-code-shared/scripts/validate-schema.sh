#!/usr/bin/env bash
# Validates <input-path> against <schema-path> using python3 + jsonschema.
# Exit 0: valid. Non-zero: invalid (error to stderr).
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: validate-schema.sh <schema-path> <input-path>" >&2
  exit 1
fi

SCHEMA_PATH="$1"
INPUT_PATH="$2"

if ! python3 -c "import jsonschema" 2>/dev/null; then
  echo "Error: jsonschema not installed. Run: pip install jsonschema" >&2
  exit 1
fi

if [ ! -f "$SCHEMA_PATH" ]; then
  echo "Error: schema file not found: $SCHEMA_PATH" >&2
  exit 1
fi

if [ ! -f "$INPUT_PATH" ]; then
  echo "Error: input file not found: $INPUT_PATH" >&2
  exit 1
fi

python3 - "$SCHEMA_PATH" "$INPUT_PATH" <<'PYEOF'
import sys, json, jsonschema

schema_path, input_path = sys.argv[1], sys.argv[2]

try:
    schema = json.load(open(schema_path))
except json.JSONDecodeError as e:
    print(f"Error: schema file is not valid JSON: {e}", file=sys.stderr)
    sys.exit(1)

try:
    instance = json.load(open(input_path))
except json.JSONDecodeError as e:
    print(f"Error: input file is not valid JSON: {e}", file=sys.stderr)
    sys.exit(1)

try:
    validator_cls = jsonschema.validators.validator_for(schema)
    validator = validator_cls(schema)
    errors = sorted(validator.iter_errors(instance), key=lambda e: list(e.path))
    if errors:
        for err in errors:
            path = " -> ".join(str(p) for p in err.absolute_path) or "(root)"
            print(f"Validation error at {path}: {err.message}", file=sys.stderr)
        sys.exit(1)
except jsonschema.exceptions.SchemaError as e:
    print(f"Error: schema itself is invalid: {e.message}", file=sys.stderr)
    sys.exit(1)
PYEOF
