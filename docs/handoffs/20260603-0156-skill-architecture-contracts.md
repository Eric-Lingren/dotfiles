# Handoff: Skill Architecture Contracts

**Date:** 2026-06-03
**Branch:** `prototype/proto-contracts-overview` (prototype branch — must be resolved before continuing main work)
**Main work branch:** `feat/skill-architecture-contracts`

## What was done

All 7 tasks in `docs/tasks/20260603-0113-skill-architecture-contracts.json` are `done`. The full Design-by-Contract system for shared skill formats is implemented but not yet committed.

### Work completed (uncommitted, on feat/skill-architecture-contracts)

**New directory: `claude-code-shared/contracts/`**
- `task-schema.json` — JSON Schema (v2020-12), schema_version const "1", additionalProperties: false, no source_branch, has linear_url
- `task-contract.md` — names producers, consumers, filename script
- `seed-schema.json` — promoted from to-prd-html/resources/prd-data-schema.json, schema_version const "2", additionalProperties: false
- `seed-contract.md` — documents the HTML PRD intermediate format and extract-prd-json.sh chain
- `runner-result-schema.json` — moved from resources/, schema_version const "1" added
- `runner-result-contract.md` — canonical version
- `OVERVIEW.md` — ASCII diagram + format table

**New script: `claude-code-shared/scripts/validate-schema.sh`**
- python3 + jsonschema (Draft 2020-12)
- Exit 0 = valid, non-zero = invalid with clear stderr
- Hard-fails with "pip install jsonschema" if library missing

**New tests: `claude-code-shared/scripts/tests/`**
- `test-contracts-structure.sh` — 23 assertions verifying contracts/ structure and schema invariants
- `test-validate-schema.sh` — 4 fixture tests (valid, missing-field, wrong-version, extra-field)

**SKILL.md changes (## Contract sections added):**
- Task producers: `to-tasks`, `to-e2e-tasks`, `debug`, `improve-component`, `code-review`
- Task consumers: `run-tasks`, `run-task-followups`, `tasks-to-linear`
- Seed producer: `prototype` (conditional — end-of-run save prompt added)
- Seed consumers: `to-tasks`, `to-prd-html`
- Runner agents: `lint-runner.md`, `test-runner.md`, `e2e-runner.md`

**Additional changes:**
- `register-skill/SKILL.md` — format contract gate (step 1b) hard-FAILs if format signal found without `## Contract` section
- `install.sh` — `pip install jsonschema` added to bootstrap
- `to-e2e-tasks/SKILL.md` — `source_branch` removed from schema illustration
- Malformed-input eval scenarios added to: `improve-skill/runs/run-tasks/`, `run-task-followups/`, `tasks-to-linear/`, `to-tasks/eval.json`, `to-prd-html/eval.json`

**Additional fixes (post-task session):**
- `task-contract.md` and `seed-contract.md` now reference naming scripts instead of static format strings
- `seed-contract.md` documents the HTML PRD as rendered seed + extract-prd-json.sh chain
- `to-prd-html/SKILL.md` documents it as both consumer (seed) and producer (HTML PRD)
- `to-tasks/SKILL.md` updated: consumes seed OR HTML PRD, Step-0a handles both

## Current state: prototype branch must be resolved first

The session ended on a prototype branch created during a `/prototype` session for `contracts/OVERVIEW.md`.

**Prototype question:** What is the best visual representation of the contracts overview?

**Verdict:** V1 (single end-to-end Mermaid flowchart) is the preferred format.

**Prototype file:** `docs/prototypes/contracts-overview-proto.html`

### Next: complete the prototype workflow

The `/prototype` skill has a defined teardown sequence (see `skills/prototype/SKILL.md`):

1. Write `docs/prototypes/20260603-0147-contracts-overview.md` using `prototype-template.md`. Slug: `contracts-overview`.
2. Ask user to confirm the artifact.
3. Commit scaffolding code to `prototype/proto-contracts-overview`.
4. Commit artifact separately.
5. Cherry-pick artifact commit onto a `prototype/contracts-overview` branch off `feat/skill-architecture-contracts`.
6. Push and open PR targeting `feat/skill-architecture-contracts`.
7. Confirm with user, then delete `prototype/proto-contracts-overview`.
8. Prompt: save as seed, handoff, or neither (likely "neither" since this is a visual prototype, not a feature).

### Then: commit the main contracts work

After the prototype is resolved, switch to `feat/skill-architecture-contracts` and commit everything. Suggested commit message:

```
feat: design-by-contract guards for shared skill formats

- Add contracts/ directory with JSON Schemas for task, seed, runner-result
- Add validate-schema.sh (python3+jsonschema, hard-fail on missing import)
- Add deterministic fixture tests for validate-schema.sh
- Add ## Contract sections to all format-touching skills and agents
- Add format gate to register-skill (hard-FAIL if format signal without Contract)
- Add malformed-input eval scenarios to 5 format-consuming skills
- Add jsonschema to install.sh bootstrap
- Remove source_branch from to-e2e-tasks
- Promote linear_url as documented optional field in task-contract.md
```

## Planned follow-ups

From `docs/tasks/20260603-0113-skill-architecture-contracts.json`:

**FU-001** — Run improve-skill evals to verify malformed-input scenarios:
- `/improve-skill run-tasks`
- `/improve-skill run-task-followups`
- `/improve-skill tasks-to-linear`
- `/improve-skill to-tasks`
- `/improve-skill to-prd-html`

**FU-002** — Audit other repos for un-versioned task files:
- `find ~ -name '*.json' -path '*/docs/tasks/*' 2>/dev/null | head -50`
- For each: check `schema_version` field, add `"schema_version": "1"` if missing
- Validate with `validate-schema.sh contracts/task-schema.json <file>`

## Key file paths

| Artifact | Path |
|---|---|
| Task file | `docs/tasks/20260603-0113-skill-architecture-contracts.json` |
| Seed file | `docs/seeds/20260603-0055-skill-architecture-contracts.json` |
| Contracts dir | `claude-code-shared/contracts/` |
| Validator script | `claude-code-shared/scripts/validate-schema.sh` |
| Test scripts | `claude-code-shared/scripts/tests/` |
| Prototype HTML | `docs/prototypes/contracts-overview-proto.html` |
| Overview doc | `claude-code-shared/contracts/OVERVIEW.md` |

## Suggested skills

1. **Complete the prototype teardown first.** Read `skills/prototype/SKILL.md` step 9 onward. Write the findings artifact, commit, cherry-pick, PR, delete branch.
2. `/run-task-followups docs/tasks/20260603-0113-skill-architecture-contracts.json` — walk through FU-001 and FU-002 after the main work is committed.
3. `/improve-skill run-tasks` — verify the malformed-input eval scenario passes.
