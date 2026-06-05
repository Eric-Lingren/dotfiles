---
name: tldr-tech
description: Summarize a technical document (code docs, API references, changelogs, config option lists, etc.) into four structured views: Engineer Concise, Engineer Full, Product Concise, Product Full. Use when user wants a structured breakdown of a technical document, config reference, or API spec.
model: sonnet
effort: high
---

Summarize the following technical content across four outputs. Use simple markdown throughout — bullets, bold, short lines. No long prose blocks. Everything must be skimmable at a glance.

**Input handling:**
- If the argument looks like a file path, read the file first.
- If the argument looks like a URL, fetch it first.
- Otherwise treat the argument as the raw content to summarize.

---

## ENGINEER - Concise

- Dense bullets only.
- **Bold** key terms: file names, functions, endpoints, config keys, flags, versions.
- What it is and what it does — nothing else.
- No narrative, no explanation of the obvious.

---

## ENGINEER - Full

- Bullets and **bold** throughout.
- Preserve everything: A vs B tradeoffs, edge cases, caveats, open questions.
- Use sub-bullets for detail, not paragraphs.
- Flag anything that affects implementation decisions.
- Scale depth to complexity — some things need real explanation, keep it in bullets.

---

## PRODUCT - Concise

- 2-4 bullets max.
- **Bold** the business or product impact.
- What changed or what this enables, and why it matters.
- Zero jargon, zero technical internals unless they affect scope or timeline.

---

## PRODUCT - Full

- Bullets and **bold** throughout.
- Cover: what it does, what it changes, what decisions it affects, risks and tradeoffs.
- Flag open questions or blockers a PM needs to know about.
- Skip implementation detail unless it creates a constraint.
- Plain language — not dumbed down, just jargon-free.

---

**Rules across all four:**

- No filler, no "this document outlines...", no throat-clearing.
- No long text blocks — if it is more than 2 lines, break it into bullets.
- Tradeoffs and caveats are never optional — always include them.
- Scale length to content complexity, not a fixed count.
- Flag ambiguities or open questions where relevant.

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
