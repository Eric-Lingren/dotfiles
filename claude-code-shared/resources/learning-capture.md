# Shared Learning Capture Block

Run this as the FINAL action of the skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Always spawn the agent — it determines whether
anything is worth recording. Do not self-assess and skip.

Always spawn the `capture-learning` agent (`subagent_type: capture-learning`).
Pass:
- `skill`: the slug provided in the skill stub that referenced this file
- `transcript_path`: resolve via bash before spawning:
  ```bash
  CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  encoded_cwd=$(pwd | sed 's|[./]|-|g')
  transcript_path="${CLAUDE_CONFIG_DIR}/projects/${encoded_cwd}/${CLAUDE_CODE_SESSION_ID}.jsonl"
  echo "$transcript_path"
  ```
  Run this command and capture the output. Pass the resulting absolute path explicitly.
- `brief_evidence`: one-sentence summary of what happened this run (what the skill
  did, any backtracks, tool failures, or user corrections observed)

The agent identifies the `trigger` (tool_failure | backtrack | user_correction |
instruction_gap | redundant_effort | uncategorized), builds a schema-valid entry,
runs grounding verification, and writes if grounded. If nothing is worth recording,
the agent exits cleanly — but the spawn must always happen.
