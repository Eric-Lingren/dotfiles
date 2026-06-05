---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
argument-hint: "[optional: path to a seed or handoff doc to resume from]"
model: opus
effort: xhigh
---

## Resume mode

**Trigger:** argument-presence detection. If ARGUMENTS contains a path, this is a resume. Do not inspect the schema or validate the file type — just check whether a path was passed.

**On resume, read the file at the given path and check for `open_threads`:**

**(a) open_threads is non-empty:** enter resume mode.
- Treat `decisions` (from the seed or handoff's embedded base seed) as settled givens. Do not re-litigate them.
- Treat `disposed_threads` as the off-limits lock list. Load every id from this list. Do not allow any thread matching a locked id to be raised again — not even under a different name. Relabel-resurrection (same semantic content, different wording) is blocked.
- Drill only the `open_threads` items. Each one is a judgment call that must be resolved, deferred, or rejected before the session ends.
- Apply the standard one-question-per-turn protocol to each open thread in sequence.

**(b) open_threads is empty (status: ready):** stop immediately.
- Tell the user: "This seed is already solidified — all threads are resolved. No grilling needed."
- Suggest next steps: `/to-tasks <path>` to generate tasks, or `/to-prd-html <path>` to render a PRD.
- Do not start a grill session.

**(c) path is unreadable or missing:** say so plainly and ask what the user wants.
- Do not guess or fall back to a fresh grill. State the exact error and stop until the user responds.

---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.

For each question:
1. Ask exactly ONE question per turn. One question mark. No sub-questions, no compound "X and Y?" questions, no follow-ups in the same message.
2. Provide your recommended answer for the question you ask. State what you think the answer should be and why.
3. When asking your first question, briefly signal the other major branches of the decision tree you plan to explore later, so the user knows you see the full picture.

Before formulating your question, if the answer could be in the codebase, spawn a read-only Haiku subagent for file exploration rather than reading files inline. If a question can be answered by reading code or project files, delegate that lookup to a Haiku subagent instead of asking the user.

## Session end protocol

When all major branches are resolved, signal the end explicitly:

> "Grill session complete. All branches resolved."

Then ask the user ONE question using `AskUserQuestion`:

> "What would you like to do with this?"

Options:
- **Create a seed** - capture decisions and context as a JSON IR (runs `/to-seed`). From there you can render a PRD, generate tasks, or prototype.
- **Nothing yet** - session was just for thinking it through

**CRITICAL RULES:**
- Do NOT implement any code, create any files, or make any changes after the grill session ends without explicit user authorization from this question.
- Answering "yes" or "yep" to a specific scoped question during the session ("do I have permission to delete X?") does NOT authorize broader implementation. Specific questions have specific scope.
- Wait for the user's answer before doing anything.

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
