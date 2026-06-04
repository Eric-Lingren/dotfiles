# Handoff: Harden the Brainstorming/Ideation Loop

**Date:** 2026-06-03
**Status:** Draft seed written. Two open threads remain before the design is ready for task generation.
**Suggested skill:** `/grill-me docs/handoffs/20260603-2313-harden-ideation-loop-pipeline.md`

---

## What this is about

Design session to harden the `grill → to-seed → loop` workflow at the front of the AI pipeline. The goal is a reliable, repeatable ideation loop that produces verified, hallucination-free seed artifacts. All major architectural branches were resolved. Two threads were cut short when the context window ran out before the user could evaluate the proposals.

---

## What is resolved (do not re-grill these)

The full design was agreed and locked across ~12 major questions:

- Loop ownership stays in `to-seed` + grill skills. No new controller.
- `to-seed` tail-calls the grill skill with the seed path on draft. Both loop paths (same-window, cross-window) share one resume contract.
- Resumed grill drills `open_threads` only. Contradiction-only reopen of settled decisions. Full context loaded from handoff + base seed.
- Grill resume triggered by argument presence. Mode-aware: fresh = live-only, resume = settled givens + `open_threads` as agenda. Three distinct exits (resume / already-solid / unreadable). No silent re-grill.
- Grill stays free (no hard gates). Soft dimension list added as anti-rabbit-hole guidance only.
- All verification guardrails live inside `to-seed` as a mandatory internal stage. Atomic. No seed commits without passing the panel.
- Synthesis does the honest first pass. Adversary panel reconciles on top (additions auto-apply, removals must cite transcript).
- Adversarial framing: panel's job is to disprove, not validate. Content presumed real unless refuted. Completeness presumed incomplete unless panel fails to surface new threads.
- 4 Haiku adversary personas: Grounding, Accuracy, Completeness, Coherence. Each carries a sub-lens checklist. All 4 run every time.
- 3 Sonnet High judges. Flat 2-of-3 majority. Transcript is ground truth.
- Thread identity: `open_threads` becomes `[{id, text, first_seen_iteration}]`. Stable ids across iterations.
- New `disposed_threads: [{id, text, disposition, iteration}]` lock list. Panel cannot re-raise a locked id. Relabel-resurrection guard in Coherence persona.
- Sticky-lock order: synthesis builds lock list first, panel and judges receive it as hard constraint.
- New `iteration: integer` field. Powers persistence nudge and context-switch proxy.
- Verification stamp: `{iteration, personas[], refutations_upheld, clean}`. Counts only, not full refutation detail.
- Seed lineage: chained new files per iteration. `ready` seed is the unambiguous downstream input. Drafts are ephemeral scaffolding.
- Exit mechanism: per-thread human disposition (decide / defer / reject) in natural conversation. Sticky by locked id. No blind iteration cap.
- Model stack: Haiku personas, Sonnet High judges.
- Domain-role personas deferred to grill phase as optional user-summoned lenses.

---

## Open threads (agenda for next session)

These are the two threads to resolve. Do not move forward to `/to-tasks` until both are closed.

**OT-1: Draft gate behavior**

How does `to-seed` present its choices after writing a draft seed?

The proposed design was:
- Offer three choices via `AskUserQuestion`: (1) continue grilling here (tail-call grill with seed path), (2) write a handoff and stop (cross-window pickup), (3) just stop and leave the draft.
- Generate the handoff doc only when the user picks option 2, not on every draft.

The user said "you're losing me here" before evaluating this. The whole question needs to be walked cleanly in the next session. Start here.

**OT-2: Context-switch nudge mechanism**

When should `to-seed` recommend switching windows vs continuing in the same window?

The proposed proxy: `iteration` counter. Below a threshold (e.g., iteration 1-2) → recommend continue-here. At or above it → recommend handoff path. User makes the final call; this is a nudge, not a gate.

The user did not evaluate this proposal. It needs to be confirmed or replaced.

---

## Deferred (do not re-raise these)

- Exact soft dimension list wording for grill
- Exact sub-lens checklists for each of the 4 personas
- Which grill variant to re-invoke on ambiguous resume (default: grill-me)
- Domain-role personas as optional grill lenses
- Panel failure handling (agent errors/timeouts)
- Shared file location for persona instructions

---

## Seed Context

```json
{
  "base_seed": "docs/seeds/20260603-2312-harden-ideation-loop-pipeline.json",
  "open_threads": [
    "Draft gate behavior: how to-seed presents the three-way choice (continue grilling here / write handoff and stop for cross-window pickup / just stop) after writing a draft seed, and when the handoff doc is generated (only on cross-window choice vs always). Discussion started in Q12 but user did not evaluate or confirm before context ran out.",
    "Context-switch nudge mechanism: iteration count was proposed as a proxy for 'context is getting heavy, recommend switching windows,' but the specific threshold, how the recommendation is surfaced, and whether it is the right proxy were not confirmed."
  ]
}
```
