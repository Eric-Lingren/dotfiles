# Handoff: dispatch-tasks pipeline

**Base seed:** `docs/seeds/20260606-0007-dispatch-tasks-pipeline.json` (status: draft, verified)
**Branch:** `feat/dispatch-tasks-pipeline`
**Status:** 2 open threads remain. Resolve them, then the seed flips to `ready` and `/to-tasks` can run.

## What this is

A grill session resolved the architecture for fixing a real defect: `to-tasks` silently drops a seed's `deferred[]` items. The fix grew into a general execution layer. The base seed holds all 20 locked decisions and full context. This handoff exists only to carry the **two unresolved scoping threads** into the next session.

## The agenda (resolve these two)

### ot-001 — Where do the configs live?
Where should the **executor registry**, the **terminus registry**, and the **per-repo domain binding** live as config?
- **Recommendation (unconfirmed):** a manifest in `claude-code-shared/`, modeled on the existing `model-tiers.json` pattern.
- Decide: one combined manifest or separate files? How does `dispatch-tasks` read the per-repo domain binding from cwd?

### ot-002 — Which terminus adapters ship in v1?
v1 builds two executors (`build-code` inline, `export-tasks` agent). But `export-tasks` needs at least one terminus adapter to do anything.
- **Option A:** GitHub Issues + Notion adapters first, to dogfood *this* dotfiles repo end to end (code -> GitHub, non-code -> personal Notion).
- **Option B:** Linear first, by converting the existing `tasks-to-linear` skill into the first terminus adapter (lowest new-code path, but doesn't exercise the dotfiles dogfood loop).
- Decide which adapter(s) are in the v1 cut.

## Decisions already locked (do NOT re-litigate)

The base seed's `decisions[]` is the source of truth. Highlights:
- Capture `deferred[]` into the task file as `task_type: triage` items. No surfacing, no auto-seeding.
- Two-axis routing: `task_type` -> executor; `(deliverable, domain)` -> terminus.
- Two-mode executor registry: `inline-skill` vs `spawn-agent`. Needs-own-thread = agent.
- Skill topology: `to-tasks` [modified], `dispatch-tasks` [new], `build-code` [renamed run-tasks], `export-tasks` [new, absorbs tasks-to-linear].
- `dispatch-tasks` is re-entrant; the JSON is the state machine; one `task_type` branch per invocation; announce-plan + auto-order (export-first) + override-at-announce.
- Termini by deliverable: code -> GitHub Issues (per repo); non-code -> 3 zones (corporate Linear hard wall, Spawned Sapien Notion, personal Notion area-tagged).
- Segregation: corporate + personal are hard walls; a domain earns its own terminus when another human or contract enters.

## Locked dispositions (off-limits — relabel-resurrection blocked)

- ot-003 surface-vs-encapsulate -> **decided** (encapsulate in task file)
- ot-004 GitHub Issues as general terminus -> **rejected** (code-only)
- ot-005 two-zone pool vs three zones -> **decided** (three zones)
- ot-006 verb names vs `<type>-tasks` convention -> **decided** (verbs)
- ot-007 dispatch ordering -> **decided** (announce + auto-order + override)
- ot-008 terminus-writer name -> **decided** (`export-tasks`)

## Suggested skills for the next session

- `/grill-me docs/handoffs/20260606-0008-dispatch-tasks-pipeline.md` — drill the two open threads, then to-seed merges resolutions back onto the base seed.
- `/grill-with-docs docs/handoffs/20260606-0008-dispatch-tasks-pipeline.md` — same, but challenge against CONTEXT.md / ADRs and update docs inline.

## Seed Context
```json
{
  "base_seed": "docs/seeds/20260606-0007-dispatch-tasks-pipeline.json",
  "open_threads": [
    {"id": "ot-001", "text": "Where should the executor registry, terminus registry, and per-repo domain binding configs live? Recommended: a manifest in claude-code-shared/ modeled on model-tiers.json, but not confirmed.", "first_seen_iteration": 1},
    {"id": "ot-002", "text": "Which terminus adapters ship in v1 — GitHub Issues + Notion to dogfood this dotfiles repo, or Linear first via the tasks-to-linear conversion?", "first_seen_iteration": 1}
  ],
  "disposed_threads": [
    {"id": "ot-003", "text": "Should deferred items be surfaced to the user / auto-promoted into new seeds, or encapsulated in the task file?", "disposition": "decided", "iteration": 1},
    {"id": "ot-004", "text": "Use GitHub Issues as the general terminus for all triage items?", "disposition": "rejected", "iteration": 1},
    {"id": "ot-005", "text": "Collapse termini to two zones (corporate wall + one consolidated AI-filtered pool) vs three explicit zones?", "disposition": "decided", "iteration": 1},
    {"id": "ot-006", "text": "Executor naming: verb-style vs <task_type>-tasks convention?", "disposition": "decided", "iteration": 1},
    {"id": "ot-007", "text": "Multi-type dispatch ordering: forced user prompt vs silent auto vs announce-plan + auto-order + override?", "disposition": "decided", "iteration": 1},
    {"id": "ot-008", "text": "Name for the terminus-writer executor (create-tickets / file-tickets / queue-tasks / create-tasks / save-tasks / push-tasks)?", "disposition": "decided", "iteration": 1}
  ]
}
```
