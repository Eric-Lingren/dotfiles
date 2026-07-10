---
name: relay
description: >
  STUB. Reply egress skill for PR feedback items. Posts threaded GitHub replies and resolves
  threads. Deferred until write-back UX and error cases are properly designed. Until built,
  revise-pr Step 9 drafts copy-only reply text inline (no external calls); relay owns the posting.
model: sonnet
effort: medium
---

This skill is a stub. It is not yet functionally implemented.

It serves as a wiring anchor in `skill-pipeline.json` for the revise-pr pipeline egress.
When built, `relay` will post threaded GitHub replies and resolve threads. Until then, `revise-pr`
Step 9 drafts copy-only reply text inline (terminal print, zero external calls) for every substantive
item, and prints a no-external-calls banner so the user can paste manually and verify nothing was sent.

<!-- learning-capture:start -->
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: relay -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `relay`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
<!-- skill-done: relay -->
<!-- learning-capture:end -->
