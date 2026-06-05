---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
model: sonnet
effort: medium
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to `docs/handoffs/` in the current workspace. Create the directory if it does not exist.

Name the file by running:

```bash
~/.dotfiles/claude-code-shared/scripts/doc-filename.sh <slug> md
```

Where `<slug>` is a short kebab-case description of the work (e.g. `auth-refactor`). The output is `YYYYMMDD-HHMM-<slug>.md`.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

<!-- learning-capture:start -->
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: handoff -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `handoff`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
<!-- skill-done: handoff -->
<!-- learning-capture:end -->
