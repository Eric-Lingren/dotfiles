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

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: fact-check -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `fact-check`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
<!-- skill-done: fact-check -->
<!-- learning-capture:end -->
