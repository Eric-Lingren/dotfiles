---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
argument-hint: "[optional: path to a seed or handoff doc to resume from]"
model: opus
effort: xhigh
---

## Resume mode

**Trigger:** argument-presence detection. If ARGUMENTS contains a path, this is a resume. Do not inspect the schema or validate the file type — just check whether a path was passed.

**On resume, route the path through resolve-ref.sh before reading** (see `resources/resolve-ref-pattern.md`):
- Run `bash ~/.dotfiles/claude-code-shared/scripts/resolve-ref.sh $(basename <path>)`. On archive hit (output starts with `ARCHIVE:`), use the extracted content. On not-found (exit non-zero), surface the diagnostic and ask "Continue anyway?" — bypass rebuilds context from conversation. Then:

**Check for `open_threads`:**

**(a) open_threads is non-empty:** enter resume mode.
- Treat `decisions` (from the seed or handoff's embedded base seed) as settled givens. Do not re-litigate them.
- Treat `disposed_threads` as the off-limits lock list. Load every id from this list. Do not allow any thread matching a locked id to be raised again — not even under a different name. Relabel-resurrection (same semantic content, different wording) is blocked.
- Drill only the `open_threads` items. Each one is a judgment call that must be resolved, deferred, or rejected before the session ends.
- Apply the standard one-question-per-turn protocol to each open thread in sequence.

**(b) open_threads is empty (status: ready):** stop immediately.
- Tell the user: "This seed is already solidified — all threads are resolved. No grilling needed."
- Show next steps by running: `python3 ~/.dotfiles/claude-code-shared/scripts/print-skill-next-steps.py grill-me` and printing the output.
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

Then print a text recommendation — do NOT use `AskUserQuestion` or any blocking UI element:

> "Next: `/to-seed` to capture these decisions as a JSON IR, then `/to-tasks` or `/to-prd-html` from there."

**CRITICAL RULES:**
- Do NOT implement any code, create any files, or make any changes after the grill session ends unless the user explicitly asks.
- Answering "yes" or "yep" to a specific scoped question during the session does NOT authorize broader implementation. Specific questions have specific scope.
- Do not block. Print the suggestion and stop.

<!-- learning-capture:start -->
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: grill-me -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `grill-me`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
**What's next:**
<!-- skill-done: grill-me -->
  - `/to-seed` — decisions are crisp and ready to capture
<!-- learning-capture:end -->
