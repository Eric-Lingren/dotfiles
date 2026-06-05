#!/usr/bin/env python3
"""stop-hook.py — learning-eval safety net.

Fires on the Stop event. Reads the last assistant turn from the transcript and
checks for skill-done/learning-eval HTML-comment markers.

Outcomes per detected skill completion (skill-done present):
  - ran:    both markers present → log it, exit silently
  - nudged: skill-done present, learning-eval absent, not yet nudged this session
            → log it, output a continue:true JSON nudge

Per-session state stored at HOOK_SESSION_DIR/cc-nudged-<session_id>.json (or
/tmp/cc-nudged-<session_id>.json by default) to prevent double-nudges.

Audit log appended to HOOK_AUDIT_DIR/hook-audit.jsonl (default:
~/.dotfiles/claude-code-shared/learnings/audit/hook-audit.jsonl).

Environment overrides (for testing):
  HOOK_AUDIT_DIR    — override the audit log directory
  HOOK_SESSION_DIR  — override the per-session state directory (default /tmp)
"""

import fcntl
import json
import os
import pathlib
import re
import sys
from datetime import datetime, timezone

SHARED = pathlib.Path(__file__).resolve().parents[1]
_audit_dir_override = os.environ.get("HOOK_AUDIT_DIR")
_session_dir_override = os.environ.get("HOOK_SESSION_DIR")

AUDIT_DIR = pathlib.Path(_audit_dir_override) if _audit_dir_override else SHARED / "learnings" / "audit"
AUDIT_LOG = AUDIT_DIR / "hook-audit.jsonl"
SESSION_DIR = pathlib.Path(_session_dir_override) if _session_dir_override else pathlib.Path("/tmp")

SKILL_DONE_RE = re.compile(r"<!-- skill-done:\s*([^\s>]+)\s*-->")
LEARNING_EVAL_RE = re.compile(r"<!-- learning-eval:\s*([^\s>]+)\s*-->")


def get_session_id(data):
    return (
        os.environ.get("CLAUDE_SESSION_ID")
        or data.get("session_id")
        or "default"
    )


def get_state_path(session_id):
    safe_id = re.sub(r"[^a-zA-Z0-9_-]", "_", session_id)
    return SESSION_DIR / f"cc-nudged-{safe_id}.json"


def load_nudged(session_id):
    path = get_state_path(session_id)
    if path.exists():
        try:
            return json.loads(path.read_text())
        except Exception:
            return {}
    return {}


def save_nudged(session_id, state):
    path = get_state_path(session_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state))


def get_last_assistant_text(transcript_path):
    """Extract the last assistant turn text from transcript JSONL."""
    try:
        lines = pathlib.Path(transcript_path).read_text().strip().splitlines()
    except Exception:
        return ""

    for line in reversed(lines):
        try:
            turn = json.loads(line)
        except Exception:
            continue
        if turn.get("role") == "assistant":
            content = turn.get("content", "")
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                parts = []
                for item in content:
                    if isinstance(item, dict) and item.get("type") == "text":
                        parts.append(item.get("text", ""))
                return "\n".join(parts)
    return ""


def append_audit(ts, skill, outcome):
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    line = json.dumps({"ts": ts, "skill": skill, "outcome": outcome}, ensure_ascii=False) + "\n"
    with open(AUDIT_LOG, "a", encoding="utf-8") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        try:
            fh.write(line)
            fh.flush()
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)


def main():
    raw = sys.stdin.read().strip()
    try:
        data = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        data = {}

    transcript_path = data.get("transcript_path", "")
    session_id = get_session_id(data)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    last_text = get_last_assistant_text(transcript_path) if transcript_path else ""

    done_slugs = SKILL_DONE_RE.findall(last_text)
    eval_slugs = set(LEARNING_EVAL_RE.findall(last_text))

    if not done_slugs:
        sys.exit(0)

    nudged_state = load_nudged(session_id)
    nudge_targets = []

    for slug in done_slugs:
        if slug in eval_slugs:
            append_audit(ts, slug, "ran")
        elif nudged_state.get(slug):
            # Already nudged this session — record as ran to avoid re-nudging
            append_audit(ts, slug, "ran")
        else:
            append_audit(ts, slug, "nudged")
            nudge_targets.append(slug)
            nudged_state[slug] = True

    if nudge_targets:
        save_nudged(session_id, nudged_state)
        slugs_str = ", ".join(nudge_targets)
        print(json.dumps({
            "continue": True,
            "decision": "block",
            "reason": (
                f"The learning-eval tail was skipped for skill(s): {slugs_str}. "
                f"Please run the learning capture tail now: "
                f"check if a correction-event occurred this run, and if so spawn "
                f"the capture-learning agent with the skill slug, trigger, "
                f"brief_evidence, and transcript_path."
            ),
        }))

    sys.exit(0)


if __name__ == "__main__":
    main()
