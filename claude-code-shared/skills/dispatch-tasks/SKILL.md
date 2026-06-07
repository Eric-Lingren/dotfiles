---
name: dispatch-tasks
description: Orchestrate a task file by partitioning items by task_type and running one branch per invocation. Routes code items to build-code (inline) and triage items to export-tasks (agent). Re-entrant — run once per branch until all items are done. Use when user wants to dispatch a mixed task file, route deferred triage items to destinations, or run one pass of the pipeline.
model: sonnet
effort: medium
---

# Dispatch Tasks

Route and execute tasks from a task file by partitioning items into branches by `task_type`, running exactly one branch per invocation. The task JSON is the durable state machine — runners mark items done in the JSON as they complete.

**Re-entrant:** run `/dispatch-tasks <path>` once per branch until all items are dispatched.

## Contract

**Format:** task file — see `contracts/task-contract.md` (schema_version: `"2"`)
**Routing config:** `~/.dotfiles/claude-code-shared/resources/task-routing.json`
**Role:** consumer and orchestrator

**Step-0 — validate input before processing:**
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  --instance ~/.dotfiles/claude-code-shared/contracts/task-schema.json \
  <input-path>
```
On non-zero exit: STOP. Report stderr to the user. Do not process the file.

## Process

### 1. Load the task file

If a path argument was passed (e.g. `/dispatch-tasks docs/tasks/20260606-0129-my-feature.json`), use it directly.

Otherwise, list all `*.json` files in `docs/tasks/` and ask the user to choose.

Read the task file. Read `~/.dotfiles/claude-code-shared/resources/task-routing.json` to get the runners map.

### 2. Partition items by task_type

Group `tasks[]` items into branches keyed by `task_type`. Exclude items with `status` of `done`, `merged`, or `blocked`.

Items without a `task_type` field are treated as `code` (legacy compatibility).

For each item in a branch, check `blocked_by`. If any blocking task has a status other than `done` or `merged`:
- Mark the item `blocked` in the task file JSON (write immediately).
- Remove it from its branch for this run.
- Add it to the end-of-run blocked summary.

### 3. Announce the plan

Print the full plan before running anything. Do not skip this step.

```
Dispatch plan — docs/tasks/<filename>

 Branch   Runner         Mode           Items
 ───────  ─────────────  ─────────────  ─────
 triage   export-tasks   spawn-agent    3
 code     build-code     inline-skill   5

Default execution order: triage first (mechanical), code last (interactive).
Override this order now, or press Enter to accept.
```

Read the `mode` and `runner` from `task-routing.json` for each branch. Show only branches that have eligible items.

Let the user override the execution order at this prompt only. Record their choice. Do not prompt again per-run.

### 4. Run one branch

Run branches in the confirmed order, **one branch per invocation**. Each invocation of `/dispatch-tasks` runs exactly one branch, then stops.

**Select the first pending branch** (ordered per step 3 confirmation). A branch is pending if it has eligible items and has not been run in this invocation.

#### code branch (inline-skill mode)

Call the `build-code` skill using the Skill tool:

```
Skill("build-code", args="<task-file-path>")
```

build-code handles branching, TDD loop, blocker detection, HITL pausing, and status updates inline. It is interactive — it may pause for user input.

After build-code returns:
- Read the task file and collect all items in the `code` branch now marked `done`.
- If build-code halted early (any item still `not_started` or `in_progress`): note which items are pending and include them in the end-of-run summary.

#### triage branch (spawn-agent mode)

Spawn `export-tasks` as an isolated agent using the Agent tool:

```
Agent(subagent_type="export-tasks", prompt="<task-file-path>")
```

export-tasks handles destination resolution, dry-run review, external writes, and status/export_url writeback. It runs in its own context window with no memory of this session.

After the agent returns:
- Read the task file and collect all items in the `triage` branch now marked `done`.
- If any items remain `not_started` or `blocked`: note them in the end-of-run summary.

### 5. End-of-invocation summary

After the branch completes, read the task file and print a status summary:

```
Branch complete — triage / export-tasks

 ID      Title                                       Result
 ──────  ──────────────────────────────────────────  ──────
 T-0010  Round-trip read side                        done
 T-0011  Additional runners                           done
 T-0012  Remaining destination adapters               blocked (export-tasks: placeholder DB ID)

Remaining branches:
  code (build-code, inline-skill) — 5 items

Re-run to continue:
  /dispatch-tasks docs/tasks/<filename>
```

If all branches across all invocations are now `done` or `merged`, print a final summary instead:

```
All branches dispatched — docs/tasks/<filename>

 ID      Title                                   Status
 ──────  ──────────────────────────────────────  ──────
 T-0001  Bootstrap schema                        done
 T-0010  Round-trip read side                    done

All items dispatched. Run /run-task-followups for manual follow-ups.
```

### 6. Output handoff block

After the summary, always output:

```
Next steps:
  /dispatch-tasks docs/tasks/<filename>   — run the next branch
  /run-task-followups docs/tasks/<filename>   — walk through manual follow-ups
```

If all branches are done:

```
Next steps:
  /run-task-followups docs/tasks/<filename>   — walk through manual follow-ups
```

<!-- learning-capture:start -->
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: dispatch-tasks -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `dispatch-tasks`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
**What's next:**
<!-- skill-done: dispatch-tasks -->
  - `/to-e2e-tasks` — want e2e coverage for the completed changes
<!-- learning-capture:end -->
