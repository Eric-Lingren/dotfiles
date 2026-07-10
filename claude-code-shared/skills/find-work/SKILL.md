---
name: find-work
description: List spike/*, feat/*, and fix/* branches in the current repo with last commit dates. Use when user wants to find previous spikes, feature branches, fix branches, or in-progress research branches.
model: haiku
effort: low
---

# Find Work

List all `spike/*`, `feat/*`, and `fix/*` branches in the current repo to help rediscover previous research or in-progress feature work.

## Process

1. Run the `find-work.sh` script from this skill's directory:

   ```bash
   bash "$(dirname "$0")/scripts/find-work.sh"
   ```

   The script outputs a table with branch name, last commit date, commit message, and whether a `docs/prd/` directory exists on the branch.

2. If no branches found, the script prints a message and exits.

3. Display the script output to the user.

4. If the user wants to switch to one, run `git switch {branch-name}`.

<!-- learning-capture:start -->
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: find-work -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `find-work`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
<!-- skill-done: find-work -->
<!-- learning-capture:end -->
