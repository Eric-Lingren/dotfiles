---
name: fact-check
description: Manual factual-claim verification. Paste any input (tweet, article, PRD, document) and the skill spawns the fact-checker agent to extract verifiable claims, check each against live web sources, and return a report in original claim order with citable links. Use when the user invokes /fact-check or asks to verify claims before acting on content.
model: sonnet
effort: medium
---

# Fact-Check

Verify factual claims in any pasted input — from a single tweet to a full PRD — against live web sources.

The verification engine lives in the `fact-checker` agent. This skill captures your input, spawns the agent in an isolated context (so its many web searches do not pollute the main thread), and routes its report to the right output format.

The same `fact-checker` agent is the reuse point for future inline fact-checking in other skills (to-prd-html, to-tasks, run-tasks). Logic is never duplicated here.

## Steps

### 1. Capture input

Accept whatever the user pastes or provides as the content to verify. This may be:
- A single claim or tweet
- A paragraph, article, or blog post
- A full PRD, document, or task description

If no input is provided, ask: "Paste the content you want fact-checked."

### 2. Assess scale

Count the approximate number of verifiable claims in the input to determine output routing:

- **Small** (1-5 verifiable claims): route to inline output (step 4a)
- **Document-scale** (6+ verifiable claims or multi-section content): route to file output (step 4b)

### 3. Spawn the fact-checker agent

Use the Agent tool with `subagent_type: fact-checker`. Pass the full input as the prompt to the agent.

The agent will:
- Run `extract-claims.py` as a deterministic pre-pass to surface candidate claims
- Extract any additional verifiable claims it finds on its own
- Verify each claim with live web search (never reasoning-only)
- Return findings in original claim order with verdict labels and citation URLs

Wait for the agent to return its structured report before proceeding.

### 4. Route output

#### 4a. Small input — inline

Relay the agent's full report verbatim inline in the conversation. Do NOT summarize, paraphrase, or strip citation URLs. Every link the agent produced must appear in your output so the user can verify findings directly. No file written.

#### 4b. Document-scale input — file + summary

Write the report to `docs/fact-checks/YYYYMMDD-HHMM-<slug>.md` where `<slug>` is a 2-3 word kebab-case description of the content checked (e.g. `q3-prd-claims`, `techcrunch-article`).

Then render a brief inline summary:
```
Fact-check complete. N claims checked.
- X FALSE/MOSTLY_FALSE — action recommended
- Y PARTLY_TRUE — review suggested
- Z UNVERIFIABLE — insufficient sources found
- W TRUE/MOSTLY_TRUE — no issues

Full report: docs/fact-checks/<filename>.md
```

### 5. Relay findings

Always present findings as advisory. Never block the user's next action. The verdict and citations are information — what to do with them is the user's call.

If any claims are FALSE or MOSTLY_FALSE, surface them explicitly in the inline summary so they are not buried in a file the user may not immediately open.

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
