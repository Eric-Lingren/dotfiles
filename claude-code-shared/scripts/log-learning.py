#!/usr/bin/env python3
"""log-learning.py — validate and append a learning entry to per-skill JSONL.

Reads a partial learning entry as JSON from stdin. Injects schema_version and
timestamp server-side, validates against learning-schema.json, then atomically
appends to claude-code-shared/learnings/<skill>.jsonl.

Usage:
    echo '{"skill":"debug","trigger":"tool_failure","trigger_label":null,...}' | python log-learning.py

The caller (a skill's managed tail block) supplies:
    skill, trigger, trigger_label, evidence, learning, suggested_fix

The script injects:
    schema_version ("1"), timestamp (ISO 8601 UTC now)

Exit 0 on success. Exit 1 on any error (printed to stderr).
"""

import fcntl
import json
import pathlib
import sys
from datetime import datetime, timezone


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
CONTRACTS_DIR = SCRIPT_DIR.parent / "contracts"
SCHEMA_PATH = CONTRACTS_DIR / "learning-schema.json"
LEARNINGS_DIR = SCRIPT_DIR.parent / "learnings"


def _build_validator(schema):
    import re
    try:
        from importlib.metadata import version as pkg_version
        v = pkg_version("jsonschema")
    except Exception:
        import jsonschema
        v = jsonschema.__version__
    m = re.match(r"(\d+)\.(\d+)", v)
    major, minor = (int(m.group(1)), int(m.group(2))) if m else (0, 0)

    use_registry = (major > 4) or (major == 4 and minor >= 18)
    if use_registry:
        try:
            from referencing import Registry, Resource
            from referencing.jsonschema import DRAFT7
            from jsonschema import Draft7Validator

            all_schemas = {}
            for sf in sorted(CONTRACTS_DIR.glob("*.json")):
                try:
                    data = json.loads(sf.read_text())
                    if "$id" in data:
                        all_schemas[data["$id"]] = data
                except Exception:
                    pass

            resources = [
                (sid, Resource.from_contents(sdata, default_specification=DRAFT7))
                for sid, sdata in all_schemas.items()
            ]
            registry = Registry().with_resources(resources)
            return Draft7Validator(schema, registry=registry)
        except ImportError:
            pass

    from jsonschema import Draft7Validator, RefResolver
    return Draft7Validator(schema, resolver=RefResolver(
        base_uri=schema.get("$id", ""), referrer=schema, store={}
    ))


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        print("ERROR: no input on stdin", file=sys.stderr)
        sys.exit(1)

    try:
        entry = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"ERROR: stdin is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(entry, dict):
        print("ERROR: input must be a JSON object", file=sys.stderr)
        sys.exit(1)

    skill = entry.get("skill", "").strip()
    if not skill:
        print("ERROR: 'skill' field is required and must be non-empty", file=sys.stderr)
        sys.exit(1)

    # Inject server-side fields
    entry["schema_version"] = "1"
    entry["timestamp"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Load schema
    try:
        schema = json.loads(SCHEMA_PATH.read_text())
    except Exception as e:
        print(f"ERROR: could not load learning-schema.json: {e}", file=sys.stderr)
        sys.exit(1)

    # Validate
    try:
        validator = _build_validator(schema)
        errors = sorted(validator.iter_errors(entry), key=lambda e: list(e.absolute_path))
    except Exception as e:
        print(f"ERROR: validator setup failed: {e}", file=sys.stderr)
        sys.exit(1)

    if errors:
        for err in errors:
            path = ".".join(str(p) for p in err.absolute_path) or "(root)"
            print(f"ERROR: validation failed at {path}: {err.message}", file=sys.stderr)
        sys.exit(1)

    # Atomic append via exclusive lock
    LEARNINGS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = LEARNINGS_DIR / f"{skill}.jsonl"
    line = json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n"

    try:
        with open(out_path, "a", encoding="utf-8") as fh:
            fcntl.flock(fh, fcntl.LOCK_EX)
            try:
                fh.write(line)
                fh.flush()
            finally:
                fcntl.flock(fh, fcntl.LOCK_UN)
    except OSError as e:
        print(f"ERROR: could not write to {out_path}: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"OK: appended learning entry for skill '{skill}' to {out_path}")


if __name__ == "__main__":
    main()
