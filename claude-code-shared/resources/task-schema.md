---
name: task-schema
description: Canonical task JSON schema for all task-generating skills (to-tasks, debug, to-e2e-tasks). Single source of truth for field definitions, ID assignment, file naming, and follow_ups structure.
---

# Task JSON Schema

All task-generating skills reference this document. Do not define task JSON schemas inline in skill files.

## Top-level structure

```json
{
  "prd": "docs/prd/YYYYMMDD-HHMM-{slug}.md",
  "generated_at": "<ISO 8601 timestamp>",
  "branching": { ... },
  "tasks": [ ... ],
  "follow_ups": [ ... ]
}
```

- `prd`: PRD path this file was generated from, or `null` for debug-originated files
- `generated_at`: ISO 8601 timestamp of file creation
- `branching`: see `~/.dotfiles/claude-code-shared/resources/branching-strategy.md`
- `tasks`: array of task objects
- `follow_ups`: array of follow-up objects

## Task object

```json
{
  "id": "T-0023",
  "title": "Short descriptive title",
  "type": "AFK",
  "description": "End-to-end behavior description. Not layer-by-layer. For refactor tasks: characterization tests must be written for existing behavior before restructuring begins.",
  "acceptance_criteria": [
    "Criterion 1 — always include at least one test-related criterion",
    "Criterion 2"
  ],
  "blocked_by": [],
  "status": "not_started",
  "branch": "feat/t-0023-short-title",
  "pr": null,
  "browser_verify": {
    "url_path": "/route",
    "assertions": ["Observable behavior description"]
  }
}
```

Field rules:
- `id`: globally sequential across all task files, zero-padded to 4 digits (`T-0001`, `T-0002`, ...). Get via `~/.dotfiles/claude-code-shared/scripts/next-task-id.sh docs/tasks/`
- `type`: `"AFK"` or `"HITL"`
- `status`: `"not_started"` | `"in_progress"` | `"done"` | `"merged"` | `"blocked"`
- `blocked_by`: array of `id` strings, empty if none
- `branch`: see `branching-strategy.md`. Only populated when `branching.strategy` is `"per-task"`.
- `pr`: `null` until merged, then PR URL or number as a string
- `browser_verify`: optional. When present, run-tasks spawns the browser-checker agent after TDD passes and gates `done` on both checks passing. When `null` or absent, no browser check is run.

### browser_verify field

Shape:

```json
"browser_verify": {
  "url_path": "/the-route-to-check",
  "assertions": [
    "Visible text 'Dashboard' appears in the heading",
    "Nav link 'Reports' is visible"
  ]
}
```

- `url_path`: relative path appended to `base_url` (from `app-launch-detection.md`). Must start with `/`.
- `assertions`: array of strings describing **observable behaviors** — visible elements, navigation targets, redirect destinations. Not implementation details.
- Set to `null` or omit entirely for non-UI tasks (pure backend, config, refactor).
- E2e-authoring tasks (from `to-e2e-tasks`) must **not** carry `browser_verify` — TDD runs the Playwright spec directly as its gate.
- A `browser_verify` task reaches `done` only when **both** TDD acceptance criteria **and** the browser check pass. A `skipped` browser check result does not block; a `fail` triggers the retry loop described in `browser-check-result.md`.

## Follow-up object

```json
{
  "id": "FU-001",
  "title": "Short description of manual action",
  "steps": [
    "Step 1 with exact command, SQL, config key, or dashboard click path",
    "Step 2 ..."
  ],
  "trigger_task": "T-0024",
  "source": "planned"
}
```

Field rules:
- `id`: sequential within this file, zero-padded to 3 digits (`FU-001`, `FU-002`, ...). Assign by counting existing `follow_ups` in the current file.
- `title`: short description of the manual action
- `steps`: ordered array. Each step must be specific: exact command, exact SQL, exact config key, or exact dashboard click path. Never write "update X" without specifying where and how.
- `trigger_task`: task ID string (e.g. `"T-0024"`) or `null` if general
- `source`: `"planned"` (from PRD or debug session) or `"discovered"` (found during run-tasks)

## ID assignment

Run `~/.dotfiles/claude-code-shared/scripts/next-task-id.sh docs/tasks/` to get the next available task ID. The script scans all JSON files in the directory and returns the next globally unique ID.

**Path rule:** The scripts live at `~/.dotfiles/claude-code-shared/scripts/`. Never substitute `~/.cch/`, `~/.claude/`, or any other directory. If the script is not found at that path, stop and tell the user rather than guessing an alternate location.

## File naming

Run `~/.dotfiles/claude-code-shared/scripts/task-filename.sh <slug>` to generate the output filename. Returns `YYYYMMDD-HHMM-{slug}.json` using the current timestamp.

**Path rule:** Same as above. Always `~/.dotfiles/claude-code-shared/scripts/task-filename.sh`. Do not substitute any other path.

## Overwrite vs merge

If a file for the same slug already exists (any prefix), ask the user:
- **Overwrite**: replace entirely. Re-run `next-task-id.sh` excluding this file to get fresh IDs.
- **Merge**: keep existing task statuses/PRs, add/update task definitions. New tasks continue from current global max.

In both cases, keep the existing filename prefix.
