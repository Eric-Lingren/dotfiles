# Handoff: Skill Architecture Contracts (Grill Session, Part 1)

**Date:** 2026-06-02
**Next session focus:** Continue `/grill-me` on this same topic. Q5 (rollout) was unanswered when context ran out. Remaining branches listed below. Resume with `/grill-me` passing this file as the argument.

**Prior handoff (full context + background):** `docs/handoffs/20260602-2329-skill-architecture-contracts.md`

---

## What Was Grilled

Stress-testing the plan to add Design by Contract + Fail Fast guards to `~/.dotfiles/claude-code-shared/skills/`.

---

## Decisions Resolved This Session

### Q1: Mechanism — script-backed validators (RESOLVED)
Entry checks must be **script-backed for Tier 1 (file exists) and Tier 2 (JSON shape validates)**. Prose-only "STOP if invalid" language is soft and LLMs rationalize past it under load. Tier 3 (semantic) stays prose-only because it cannot be scripted.

Exception: skills that accept freeform prose input (to-seed from conversation, grill-me) cannot have Tier 1/2 checks. Script-backed guards apply only where the input is a structured file.

### Q2: Single shared validator (RESOLVED)
One shared validator script in `claude-code-shared/scripts/` backed by one canonical JSON Schema file per format. Not per-skill bespoke validators. Reason: too many producers/consumers converge on the same formats.

### Q3: Contracts attach to the shared format (RESOLVED)
Data shape rules live in ONE schema file per format. Each skill's `## Contract` section is short: "I produce/consume `<name>-schema.json`" plus any skill-specific invariants. No hand-copying the shape into each skill.

### Q4: Location — new top-level `contracts/` folder (RESOLVED)
`claude-code-shared/contracts/` is a new first-class directory alongside `skills/`, `scripts/`, `agents/`, `resources/`. All three format pairs move here:

| Files | Source |
|-------|--------|
| `contracts/task-schema.json` + `task-contract.md` | Author `.json` from existing `resources/task-schema.md`; rename `.md` |
| `contracts/seed-schema.json` + `seed-contract.md` | Promote from `to-prd-html/resources/prd-data-schema.json` |
| `contracts/runner-result-schema.json` + `runner-result-contract.md` | Move from `resources/`; update refs in run-tasks + runner agents |

`runner-result-contract.md` does not exist today; `resources/runner-result-schema.json` does. A narrative `.md` needs to be authored.

---

## Key Facts Discovered (for the next agent)

**Two format waists (shared data shapes) + one runner contract:**

1. **Seed format** — `schema_version: "2"`. One producer (to-seed). Consumed by to-prd-html (embeds verbatim in `<script id="prd-data">`), and by to-tasks (via `extract-prd-json.sh`). A real JSON Schema already exists at `to-prd-html/resources/prd-data-schema.json`. Promote it.

2. **Tasks format** — Top-level fields: `prd`, `generated_at`, `branching`, `tasks[]`, `follow_ups[]`. No `schema_version` field yet (needs adding). Prose doc only at `resources/task-schema.md`. **Four current producers:** to-tasks, to-e2e-tasks, debug, improve-component. **Three current consumers:** run-tasks, run-task-followups, tasks-to-linear. **Two desired future producers:** prototype (emits `docs/prototypes/*.md` today), code-review (emits inline comments today). All four producers currently hand-copy the shape inline in their own SKILL.md files. This drift is the highest-priority problem.

3. **Runner result format** — Already has a real JSON Schema (`resources/runner-result-schema.json`). Used by lint-runner, test-runner, browser-checker agents → run-tasks. Move to `contracts/`, author the narrative `.md`.

**The schema vs contract distinction (clarified for user this session):**
- **Schema** = machine-readable data shape. A JSON Schema file a script can validate against. Pass/fail.
- **Contract** = full behavioral agreement: preconditions + postconditions + invariants. The schema covers one dimension (data shape). The contract is broader (behavioral rules). A `-contract.md` file is human-readable narrative. A `-schema.json` file is machine-checkable. You need both.

---

## Unanswered Questions (resume here)

### Q5: Rollout — PENDING (context ran out here)
Options:
- **Tracer bullet:** tasks waist first, end to end. One producer (to-tasks) + one consumer (run-tasks). Prove the validator mechanic works before wiring all nine skills.
- **Big-bang:** all three waists in one pass.

My recommendation going into next session: tracer bullet on the tasks waist. But the user had not answered yet.

### Q6: register-skill gate — NOT YET ASKED
Should register-skill require a `## Contract` section in SKILL.md before a skill can be registered? Today it checks agent frontmatter only.

### Q7: How a skill runs the validator — NOT YET ASKED
What is the exact mechanic? Does the skill call `bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh contracts/task-schema.json docs/tasks/foo.json`? Or does the skill just instruct the LLM to call the script? Is it a `## Entry Check` section with a literal bash command, or a tool call?

### Q8: Verification via improve-skill — NOT YET ASKED
How do we prove the guards actually fire on bad input? The improve-skill harness has behavioral scores per skill. Should eval scenarios include a deliberately malformed input and assert the skill STOPs with a useful error message?

### Q9: grill-me / grill-with-docs overlap — DEFERRED (same decision as prior handoff)
Handoff from prior session said defer. Confirm still deferred before wrapping this grill session.

---

## Key File Paths

```
claude-code-shared/resources/task-schema.md          # exists, prose only
claude-code-shared/resources/runner-result-schema.json  # exists, real JSON Schema
claude-code-shared/skills/to-prd-html/resources/prd-data-schema.json  # real JSON Schema, promote
claude-code-shared/skills/to-tasks/scripts/extract-prd-json.sh        # the one working validator today
claude-code-shared/resources/model-tiers.json        # central registry (unrelated to this work)
```

---

## Suggested Skills

- `/grill-me docs/handoffs/20260602-2357-skill-architecture-contracts-grill.md` — resume the grill from Q5
- `/to-seed` — once grill is complete, distill decisions into a seed file before implementing
- `/improve-skill` — after contracts are added, use to verify guards fire on bad input (behavioral scoring)
- `/register-skill` — may need updating once register-skill gate decision (Q6) is resolved
