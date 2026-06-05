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

**Default: write nothing.** Most runs record nothing. Only proceed if an observable
correction-event occurred this run — a tool failure you had to work around, a backtrack,
a user correction, an instruction gap, or redundant work you repeated.

### Step 1 — assess whether a correction-event occurred

If no correction-event: stop here. Do not call the judge. Do not call the writer.

### Step 2 — build a candidate entry

Construct this JSON object (do not include schema_version or timestamp; the writer injects them):

```json
{
  "skill": "<this skill's slug, e.g. debug>",
  "trigger": "<tool_failure | backtrack | user_correction | instruction_gap | redundant_effort | uncategorized>",
  "trigger_label": "<snake_case label if trigger == uncategorized, else null>",
  "evidence": "<WHAT happened this run. Observable, run-specific. For aggregated events (redundant_effort, backtrack, or any tried-N-times observation) list discrete quoted transcript anchors — not a bare count. The judge counts len(anchors).>",
  "learning": "<WHY it happened and the general reusable rule that must hold beyond this run. If this sentence only describes this run it belongs in evidence, not here.>",
  "suggested_fix": "<the concrete skill or script edit that would prevent recurrence, or null>"
}
```

Enumerate-discrete-anchors: for any aggregated observation, evidence must quote each
individual anchor explicitly. Example — correct: "Ran Glob three times: step 2 ('no
results'), step 5 ('no results'), step 8 ('found debug.jsonl')." Incorrect: "Ran Glob
three times without finding the file."

### Step 3 — grounding gate

Spawn the `learning-grounding-judge` agent (`subagent_type: learning-grounding-judge`,
model: haiku). Pass it:

```
## Entry
<candidate entry JSON>

## Transcript path
<absolute path to the session transcript file>
```

The agent returns `{"grounded": true|false, "reason": "..."}`.

### Step 4 — write or discard

If `grounded: true`:
```bash
echo '<entry JSON>' | python ~/.dotfiles/claude-code-shared/scripts/log-learning.py
```

If `grounded: false`: write nothing. The agent's reason explains what anchor was missing.
<!-- learning-capture:end -->
