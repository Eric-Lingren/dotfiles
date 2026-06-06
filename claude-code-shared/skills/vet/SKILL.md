---
name: vet
description: >
  STUB. Diligence executor for verifying PR claims against code. Takes a flagged claim and
  code pointers, verifies against actual code, and returns confirmed/false_flag/not_an_escape
  verdict. Slots into the mandatory diligence gate inside revise-pr when built.
model: sonnet
effort: high
---

This skill is a stub. It is not yet functionally implemented.

It serves as a wiring anchor in `skill-pipeline.json` for the revise-pr diligence gate.
When built, `vet` will automate what is currently a manual step: take a flagged claim plus
code pointers, verify the claim against actual code, and return a diligence verdict.

<!-- learning-capture:start -->
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: vet -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `vet`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
<!-- skill-done: vet -->
<!-- learning-capture:end -->
