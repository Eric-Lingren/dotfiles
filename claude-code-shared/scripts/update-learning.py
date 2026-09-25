#!/usr/bin/env python3
"""
update-learning.py — atomically update a learning entry's status in unified-learnings.jsonl.

Usage:
  python3 update-learning.py --id <uuid> --status <captured|applied|stale|invalid>
  python3 update-learning.py --id <uuid> --status <status> --file <path>

The update is atomic: it acquires an exclusive flock on a companion .lock file,
rewrites the JSONL to a temp file in the same directory, then replaces the
original via os.replace (atomic rename).
"""

import argparse
import fcntl
import json
import os
import sys
import tempfile
from pathlib import Path

VALID_STATUSES = {"captured", "applied", "stale", "invalid"}
DEFAULT_FILE = os.path.expanduser(
    "~/.dotfiles/claude-code-shared/learnings/unified-learnings.jsonl"
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Update a learning entry's status")
    parser.add_argument("--id", required=True, help="UUID of the entry to update")
    parser.add_argument(
        "--status",
        required=True,
        choices=sorted(VALID_STATUSES),
        help="New status value",
    )
    parser.add_argument(
        "--file",
        default=DEFAULT_FILE,
        help="Path to unified-learnings.jsonl (default: %(default)s)",
    )
    args = parser.parse_args()

    jsonl_path = Path(args.file).expanduser().resolve()
    if not jsonl_path.exists():
        print(f"error: file not found: {jsonl_path}", file=sys.stderr)
        sys.exit(1)

    lock_path = jsonl_path.with_suffix(".lock")

    # Acquire an exclusive lock via a companion .lock file so concurrent
    # invocations don't race on os.replace.
    with open(lock_path, "w") as lock_fh:
        fcntl.flock(lock_fh, fcntl.LOCK_EX)
        try:
            _update_entry(jsonl_path, args.id, args.status)
        finally:
            fcntl.flock(lock_fh, fcntl.LOCK_UN)


def _update_entry(jsonl_path: Path, target_id: str, new_status: str) -> None:
    with open(jsonl_path, "r", encoding="utf-8") as fh:
        raw_lines = fh.readlines()

    entries: list[dict] = []
    found = False
    for lineno, line in enumerate(raw_lines, 1):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"warning: skipping malformed line {lineno}: {exc}", file=sys.stderr)
            continue
        if entry.get("id") == target_id:
            entry["status"] = new_status
            found = True
        entries.append(entry)

    if not found:
        print(f"error: no entry found with id={target_id}", file=sys.stderr)
        sys.exit(1)

    # Write to a temp file in the same directory, then atomically rename.
    tmp = tempfile.NamedTemporaryFile(
        mode="w",
        dir=jsonl_path.parent,
        prefix=".update-learning-tmp-",
        suffix=".jsonl",
        delete=False,
        encoding="utf-8",
    )
    try:
        for entry in entries:
            tmp.write(json.dumps(entry, separators=(",", ":")) + "\n")
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp.close()
        os.replace(tmp.name, jsonl_path)
    except Exception:
        tmp.close()
        try:
            os.unlink(tmp.name)
        except OSError:
            pass
        raise

    print(f"updated {target_id} -> status={new_status}")


if __name__ == "__main__":
    main()
