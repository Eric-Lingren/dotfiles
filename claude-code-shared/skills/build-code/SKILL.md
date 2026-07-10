---
name: build-code
description: Execute tasks from a tasks JSON file sequentially, one build-runner spawn per task. Handles branching, status updates, blocker detection, leaf/blocker failure policy, and deferred HITL tasks without halting independent work. Use when user wants to run AI tasks from a docs/tasks/ file.
model: sonnet
effort: high
---

<!-- tier-delegate: managed by sync-model-tiers.py -->
## Delegate menial lookups to Haiku (cost control)

During this skill, push pure read-only lookups DOWN to a cheap subagent instead
of running them on the current model. This covers: multi-file grep/glob,
"where is X defined / what calls Y", mapping a directory, reading many files to
locate something, or fetching a URL for reference.

Use the Agent tool with the `caveman:cavecrew-investigator` subagent (Haiku,
returns a compressed file:line answer). If that subagent is unavailable, spawn a
general agent with `model: haiku`. Keep all reasoning, decisions, and edits on
the current model. Delegate only the menial searching.
<!-- /tier-delegate -->

# Run Tasks

Execute tasks from a `docs/tasks/` JSON file sequentially. Each AFK task is executed in isolation by the `build-runner` agent — build-code itself never runs `/tdd` inline and never holds a task's full execution trace, only the compact receipt `build-runner` returns. Updates task status in the JSON as work progresses.

## Contract

**Format:** task file — see `contracts/task-contract.md` (schema_version: `"1"`)
**Role:** consumer

**Step-0 — validate input before processing:**
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  --instance ~/.dotfiles/claude-code-shared/contracts/task-schema.json \
  <input-path>
```
On non-zero exit: STOP. Report stderr to the user. Do not process the file.

## Process

### 1. Ask for task file and target

Always ask explicitly. Do not infer from context:

1. **Which task file?** List ALL `*.json` files in `docs/tasks/` (use `ls docs/tasks/*.json` or equivalent). Files may use either naming convention:
   - Legacy: `NNNN-slug.json` (e.g. `0002-invite-domain-check.json`)
   - Timestamped: `YYYYMMDD-HHMM-slug.json` (e.g. `20260512-1600-invite-domain-check-pr-fixes.json`)

   Show every file found regardless of prefix format. Present them as numbered options with the full filename.
2. **Which task ID?** Ask for a specific task ID (e.g. `T-0005`) or leave blank to run all `not_started` tasks in order.

Route the chosen path through resolve-ref.sh before reading (see `resources/resolve-ref-pattern.md`): Run `bash ~/.dotfiles/claude-code-shared/scripts/resolve-ref.sh $(basename <path>)`. On archive hit (output starts with `ARCHIVE:`), use the extracted content. On not-found (exit non-zero), surface the diagnostic and ask "Continue anyway?" — bypass rebuilds context from conversation.

Read the chosen JSON file.

### 2. Determine the run queue

If a specific task ID was given:
- Run that single task regardless of its current status.
- Still check its `blocked_by` dependencies (see step 4).

If no task ID was given, build the queue:
- Include all tasks with status `not_started` or `failed`, in `id` order. Resumption is free: a `failed` task from a prior run is retried exactly like a fresh `not_started` task.
- Skip tasks with status `in_progress`, `done`, `merged`, `blocked`, or `deferred_hitl`.

### 3. Set up branching

Read `branching.strategy` from the JSON:

- **`"single"`** — check out or create `branching.branch` once before starting the queue. All tasks run on this branch.
- **`"per-task"`** — create each task's `branch` field value immediately before that task runs.

### 3b. Build the shared context brief (once)

Before the loop starts, if the queue is non-empty, spawn the `context-loader` agent once for the whole run:

```
Agent(subagent_type="context-loader", prompt="<project root>")
```

Capture its JSON payload as `context_brief`. Reuse this same brief for every `build-runner` spawn in this run — never re-spawn `context-loader` per task.

Initialize `breadcrumb = []` (an empty list of compact receipts from tasks completed so far this run).

### 4. For each task in the queue

#### a. Check blockers

Look up each ID in `blocked_by`. If any blocking task has a status other than `done` or `merged`:
- Mark the current task `blocked` in the JSON.
- Determine if any other `not_started` task in the queue depends on this task (i.e. has this task's ID in its `blocked_by`).
  - **If yes (it is a blocker):** halt the entire run immediately. Report which task is blocked and why. Do not process further tasks.
  - **If no (standalone):** park it, continue to the next task in the queue, add to the end-of-run summary.

#### b. Handle HITL tasks

HITL means **hands-only**: a keyboard action the AI cannot perform AFK (e.g. enable a feature flag, add a credential to a secrets manager, configure DNS, seed production data). Decision and design-review tasks are NOT valid HITL tasks — they should never appear in the queue. If they do, treat them as a bug in the task file.

If `type` is `"HITL"`: set status to `deferred_hitl` in the JSON, print the task's title, description, and acceptance criteria so the user knows a hands-on action is waiting, and continue to the next task in the queue — independent AFK work never halts for a HITL task, blocker or not. Add it to the end-of-run report's `deferred_hitl` list. If another queued task's `blocked_by` names this HITL task, that dependent task will correctly report `blocked` in step 4a until a human completes the action and flips this task's status to `done`/`merged` by hand; that is expected, not a run halt.

#### c. Execute AFK tasks

1. Update task status to `in_progress` in the JSON.
2. If `branching.strategy` is `"per-task"`, create and check out the task's branch now.
3. Spawn exactly one `build-runner` agent for this task:

```
Agent(subagent_type="build-runner", prompt="<task object JSON, context_brief, breadcrumb, taskfile_basename, project_root>")
```

Pass:
- `task` — this task's full object (`id`, `title`, `type`, `description`, `acceptance_criteria`, `browser_verify` if present).
- `context_brief` — the brief built once in step 3b.
- `breadcrumb` — the current `breadcrumb` list (receipts from tasks already completed this run).
- `taskfile_basename` — basename of the task file.
- `project_root` — absolute project root path.

build-runner runs the full `/tdd` cycle, the runner-based validation gate, and browser verification (if applicable) internally, and writes the full trace to `docs/tasks/.logs/<taskfile-basename>/<task.id>.md`. build-code never sees that trace — only the receipt below.

4. **Collect the receipt.** Parse build-runner's returned JSON: `status`, `summary`, `files_touched`, `tests`, `pr`, `log_path`, `follow_ups`.

5. **Write the receipt back into the task JSON item:**
   - Set `summary`, `files_touched`, `tests`, `log_path` directly from the receipt.
   - If `receipt.status == "done"`: set task `status` to `done` and `pr` to a suggested `gh pr create` command the user can run (do not run it).
   - If `receipt.status == "failed"`: set task `status` to `failed` and go to step 6 below — do not append to the breadcrumb.
   - Write the updated JSON immediately.

6. **Merge follow-ups.** For each item in `receipt.follow_ups`:
   - Deduplicate against existing `follow_ups` in the JSON (skip if a similar title already exists).
   - Assign `"id"` by counting existing `follow_ups` and using the next sequential `FU-XXX` (zero-padded to 3 digits).
   - Append with `"source": "discovered"` and `"trigger_task"` set to this task's ID.
   - Write the updated JSON immediately (same write as step 5).

7. **Thread the breadcrumb forward.** On success (`receipt.status == "done"`), append a compact entry — `{id, title, summary, files_touched}` — to `breadcrumb` for the caller to pass into every subsequent `build-runner` spawn this run. Never append the full trace; `breadcrumb` stays small for the life of the run.

8. If `receipt.status == "failed"`, apply the AFK obstacle policy:
   - Determine if any other `not_started` task depends on this one (a **blocker** task) or not (a **leaf** task).
   - **Leaf task failure:** status is already `failed` from step 5. Skip it, continue to the next task, add it to the end-of-run report's `failed` list (with `log_path`). Do not halt.
   - **Blocker task failure:** halt the entire run immediately. Do not process further tasks. The failure report must frame this as a **scoping signal, not a retry target**: something about this task's acceptance criteria, description, or dependency graph doesn't match reality (an unstated dependency, wrong assumption, or oversized slice), and the recommended next step is to re-grill or re-seed this part of the plan, not to blindly re-run build-code hoping for a different result. Include `log_path` so the user can inspect the full trace before deciding how to re-scope.

### 4b. Debug cleanup (only when `producer: "debug"`)

Read the root `producer` field of the tasks file. If it is `"debug"` and all fix tasks reached `done`, run the debug end-of-run cleanup automatically — this is AFK work, not a follow-up:

- Execute the "Debug cleanup and post-mortem" runbook from `~/.dotfiles/claude-code-shared/resources/hitl-steps-runbooks.md` (this is debug Phase 5): capture a pre-cleanup test baseline, remove all `[DEBUG-...]` instrumentation, delete throwaway harness files and stale `docs/browser-checks/` run dirs, re-run the suite and confirm no new failures, and state the winning hypothesis in the PR description.
- If cleanup introduces new test failures, treat it as a regression and fix before proceeding.

If `producer` is anything other than `"debug"`, skip this step.

### 5. End-of-run summary

Print a consolidated status table in the conversation. Every row that reached `done`, `failed`, `deferred_hitl`, or `blocked` gets a `Log` column pointing at its trace (blank for tasks that never reached build-runner, e.g. `blocked` from a dependency check):

```
Run complete — docs/tasks/20260512-1423-user-auth-flow.json

 ID      Title                        Result           Log
 ──────  ───────────────────────────  ──────────────  ─────────────────────────────────
 T-0023  Bootstrap auth schema        done             docs/tasks/.logs/.../T-0023.md
 T-0024  Login endpoint               done             docs/tasks/.logs/.../T-0024.md
 T-0025  Design review (HITL)         deferred_hitl    —
 T-0026  Token refresh flow           failed           docs/tasks/.logs/.../T-0026.md
 T-0027  Logout endpoint              blocked          —

Deferred HITL tasks requiring human action:
  T-0025 — Design review: confirm token storage approach

Failed / blocked tasks:
  T-0026 — Token refresh flow: leaf failure, skipped. Inspect docs/tasks/.logs/.../T-0026.md.
  T-0027 — Logout endpoint: blocked by T-0026.

If a blocker task failed (halted the run): frame it as a scoping signal, not a retry target.
Re-grill or re-seed the affected slice before re-running — see docs/tasks/.logs/.../<task>.md for the full trace.

Resumption: re-invoking build-code on this file picks up every `not_started` and `failed` task automatically.

Manual follow-ups (2):
  1. Add STRIPE_KEY to Cloudflare [T-0024, discovered]
     a. Go to Cloudflare dashboard > Workers & Pages > your-app > Settings > Variables
     b. Click 'Add variable'
     c. Name: STRIPE_KEY, Value: from Stripe dashboard > API keys
     d. Click 'Encrypt' then 'Save'

  2. Run database migration [T-0023, planned]
     a. Run `npx drizzle-kit push`
     b. Verify tables created with `npx drizzle-kit studio`

Run `/run-task-followups` for interactive walkthrough with step-by-step guidance.
```

Do not write this summary to any file.

### 6. Output handoff block

After the summary, always output:

```
Next steps:
```

Then run:
```bash
python3 ~/.dotfiles/claude-code-shared/scripts/print-skill-next-steps.py build-code
```

Append that output under the Next steps header. Do not hardcode skill names.

### 7. Offer to push and open a PR

After printing the summary, ask the user: **"Push and open a PR?"**

If the user says yes (or any affirmative), proceed:

#### a. Generate a PR description

Gather context:
- Current branch: `git rev-parse --abbrev-ref HEAD`
- Commits on branch: `git log main...HEAD --oneline`
- Diff (truncated to first 300 lines): `git diff main...HEAD | head -n 300`
- Linear ticket: extract the first `[A-Za-z]+-[0-9]+` pattern from the branch name (uppercase). This is optional — many projects don't use Linear. If a ticket is found, check CLAUDE.md or `.claude/` config for a Linear workspace URL. If one is present, include `Linear Ticket: [TICKET](<workspace-url>/issue/TICKET)`. If no workspace URL is configured, include the ticket ID as plain text only. If no ticket pattern exists in the branch name, omit this line entirely.

Then write the PR description in this exact format:

```
### <short descriptive title>
<Linear ticket link, if found>

<2-3 sentences: what was broken or missing, and what this PR does to fix it>

**Changes:**
<bullet list of key code changes — skip test files unless they are the point>
```

Rules for the description:
- Under 250 words
- No Testing section, no other sections
- No em dashes — use periods or commas only
- Concise, no run-on sentences

#### b. Push and create the PR

1. Run `~/.dotfiles/.scripts/gxpush --pr` via the Bash tool. gxpush runs non-interactively (the Proceed prompt auto-accepts empty input), so the user never sees it live.
2. After the Bash tool returns, print the full gxpush output verbatim to the user. This includes the STAGED, WILL ADD, EXCLUDED, and SECRETS sections so they can see exactly what was committed.
3. Return the PR URL to the user (gxpush prints it after `gh pr create` completes).

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `build-code`.
<!-- skill-done: build-code -->
  - `/run-task-followups` — all tasks are done and FU-001 cleanup is ready
  - `/to-e2e-tasks` — want e2e coverage for the completed changes (optional)
<!-- learning-capture:end -->
