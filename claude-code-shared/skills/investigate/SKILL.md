---
name: investigate
description: >
  STUB. Standalone external-signal explorer. Takes a Sentry ticket, Slack thread, Datadog
  signal, or open question without context and investigates it. Distinct from vet (which
  verifies flagged code claims). Part of the investigation skill family.
model: sonnet
effort: high
---

This skill is a stub. It is not yet functionally implemented.

It serves as a wiring anchor in `skill-pipeline.json`. When built, `investigate` will
explore unknown external signals (Sentry, Slack, Datadog) and surface actionable findings.
Methodology is similar to `vet` but operates on external-signal domain rather than code claims.

<!-- learning-capture:start -->
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: investigate -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `investigate`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
<!-- skill-done: investigate -->
<!-- learning-capture:end -->
