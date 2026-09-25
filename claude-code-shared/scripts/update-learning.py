#!/usr/bin/env python3
"""update-learning.py — update the status field of an existing learning entry.

Finds a learning entry in unified-learnings.jsonl by UUID, validates the new
status value against learning-schema.json, then atomically rewrites the file.

Usage:
    python update-learning.py --id <uuid> --status <new_status>

Valid status values: captured, applied, stale, invalid

Environment:
    LOG_LEARNING_DEST — override the learnings/ directory (used by tests).

Exit 0 on success. Exit 1 on any error (printed to stderr).
"""

import argparse
import fcntl
import json
import os
import pathlib
import sys
import tempfile


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
CONTRACTS_DIR = SCRIPT_DIR.parent / "contracts"
SCHEMA_PATH = CONTRACTS_DIR / "learning-schema.json"

_dest_override = os.environ.get("LOG_LEARNING_DEST")
LEARNINGS_DIR = pathlib.Path(_dest_override) if _dest_override else SCRIPT_DIR.parent / "learnings"


def _get_valid_statuses():
    """Extract allowed status values from the schema."""
    try:
        schema = json.loads(SCHEMA_PATH.read_text())
    except Exception as e:
        print(f"ERROR: could not load learning-schema.json: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        return schema["properties"]["status"]["enum"]
    except (KeyError, TypeError) as e:
        print(f"ERROR: could not read status enum from schema: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Update the status field of an existing learning entry."
    )
    parser.add_argument("--id", required=True, help="UUID of the learning entry to update.")
    parser.add_argument("--status", required=True, help="New status value.")
    args = parser.parse_args()

    entry_id = args.id.strip()
    new_status = args.status.strip()

    if not entry_id:
        print("ERROR: --id must be a non-empty string", file=sys.stderr)
        sys.exit(1)

    # Validate status against schema
    valid_statuses = _get_valid_statuses()
    if new_status not in valid_statuses:
        print(
            f"ERROR: invalid status '{new_status}'. Must be one of: {', '.join(valid_statuses)}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Locate the JSONL file
    jsonl_path = LEARNINGS_DIR / "unified-learnings.jsonl"
    if not jsonl_path.exists():
        print(f"ERROR: learnings file not found: {jsonl_path}", file=sys.stderr)
        sys.exit(1)

    # Read + lock + find + rewrite atomically
    try:
        with open(jsonl_path, "r+", encoding="utf-8") as fh:
            fcntl.flock(fh, fcntl.LOCK_EX)
            try:
                lines = fh.readlines()

                updated_lines = []
                found = False
                for line in lines:
                    stripped = line.rstrip("\n")
                    if not stripped:
                        updated_lines.append(line)
                        continue
                    try:
                        entry = json.loads(stripped)
                    except json.JSONDecodeError:
                        # Preserve malformed lines unchanged
                        updated_lines.append(line)
                        continue

                    if entry.get("id") == entry_id:
                        if found:
                            print(
                                f"ERROR: duplicate entry with id={entry_id}; file may be corrupt",
                                file=sys.stderr,
                            )
                            sys.exit(1)
                        entry["status"] = new_status
                        found = True
                        updated_lines.append(
                            json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n"
                        )
                    else:
                        updated_lines.append(line)

                if not found:
                    print(
                        f"ERROR: no entry with id={entry_id} found in {jsonl_path}",
                        file=sys.stderr,
                    )
                    sys.exit(1)

                # Write to a temp file in the same directory, then replace
                tmp_fd, tmp_path = tempfile.mkstemp(
                    dir=LEARNINGS_DIR, prefix=".update-learning-tmp-", suffix=".jsonl"
                )
                try:
                    with os.fdopen(tmp_fd, "w", encoding="utf-8") as tmp_fh:
                        tmp_fh.writelines(updated_lines)
                        tmp_fh.flush()
                        os.fsync(tmp_fh.fileno())
                    os.replace(tmp_path, jsonl_path)
                except Exception:
                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    raise

            finally:
                fcntl.flock(fh, fcntl.LOCK_UN)

    except OSError as e:
        print(f"ERROR: could not update {jsonl_path}: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"OK: updated entry id={entry_id} status -> {new_status} in {jsonl_path}")


if __name__ == "__main__":
    main()
