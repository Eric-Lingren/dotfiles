---
name: build-code
description: Execute tasks from a tasks JSON file sequentially using TDD. Handles branching, status updates, blocker detection, and HITL pausing. Use when user wants to run AI tasks from a docs/tasks/ file.
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

Execute tasks from a `docs/tasks/` JSON file sequentially, using `/tdd` for each AFK task. Updates task status in the JSON as work progresses.

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

Read the chosen JSON file and the PRD it references (`prd` field).

### 2. Determine the run queue

If a specific task ID was given:
- Run that single task regardless of its current status.
- Still check its `blocked_by` dependencies (see step 4).

If no task ID was given, build the queue:
- Include all tasks with status `not_started`, in `id` order.
- Skip tasks with status `in_progress`, `done`, `merged`, or `blocked`.

### 3. Set up branching

Read `branching.strategy` from the JSON:

- **`"single"`** — check out or create `branching.branch` once before starting the queue. All tasks run on this branch.
- **`"per-task"`** — create each task's `branch` field value immediately before that task runs.

### 4. For each task in the queue

#### a. Check blockers

Look up each ID in `blocked_by`. If any blocking task has a status other than `done` or `merged`:
- Mark the current task `blocked` in the JSON.
- Determine if any other `not_started` task in the queue depends on this task (i.e. has this task's ID in its `blocked_by`).
  - **If yes (it is a blocker):** halt the entire run immediately. Report which task is blocked and why. Do not process further tasks.
  - **If no (standalone):** park it, continue to the next task in the queue, add to the end-of-run summary.

#### b. Handle HITL tasks

HITL means **hands-only**: a keyboard action the AI cannot perform AFK (e.g. enable a feature flag, add a credential to a secrets manager, configure DNS, seed production data). Decision and design-review tasks are NOT valid HITL tasks — they should never appear in the queue. If they do, treat them as a bug in the task file.

If `type` is `"HITL"`:
- Determine if any other `not_started` task in the queue depends on this task.
  - **If yes (it is a blocker):** update status to `in_progress` in the JSON, print the task's title, description, and acceptance criteria, tell the user this task requires a hands-on human action before the pipeline can continue, and halt the run.
  - **If no (standalone):** skip it, continue to the next task, add to the end-of-run summary.

#### c. Execute AFK tasks

1. Update task status to `in_progress` in the JSON.
2. If `branching.strategy` is `"per-task"`, create and check out the task's branch now.
3. Seed `/tdd` with the following context, then invoke it:

```
## Task context for TDD

**Task:** {id} — {title}
**Type:** AFK

**Description:**
{description}

**Acceptance criteria:**
{acceptance_criteria as a checklist}

## Test requirements

Tests are mandatory for every task. This applies to new code, refactors, and moves equally.

For refactoring or restructuring tasks: check if the code being changed has existing test coverage. If not, write characterization tests for the current behavior BEFORE making any changes. Then refactor while keeping tests green.

For new code: follow the standard RED-GREEN-REFACTOR loop.

**If `acceptance_criteria[0]` says "Visual regression verified manually — no automated test seam exists":** this is a claim to verify, not a directive to skip tests. Read the code first. The following are always testable: conditional renders, query `enabled` flags, auth state branches, prop threading. The only valid skip is a CSS property difference (e.g. `blur(3px)` vs `background`) the DOM cannot reflect. If you find a seam, write the test. State why no seam exists before proceeding without one.

A task is not done until tests exist that verify the behavior described in the acceptance criteria. "Verified manually" does not satisfy this requirement.

## PRD context

{full contents of the PRD file}
```

4. If TDD completes successfully, run a runner-based validation gate before marking done:

   **a-d. Runner-based validation gate**

   1. **Detect tooling.** Run:
      ```bash
      python3 ~/.dotfiles/claude-code-shared/scripts/tooling-detection/detect_tooling.py <project_root>
      ```
      Capture the JSON manifest (one entry per workspace with resolved lint/format/typecheck/test commands).

   2. **Map touched workspaces.** Run `git diff --name-only HEAD~1` (or `git diff --name-only` for uncommitted changes). For each changed file path, find the workspace entry whose `workspace` field is a prefix of that path. Collect the unique set of touched workspaces.

   3. **Spawn runners.** Lint-runners run in parallel; test-runners run serially (one vitest/jest/pytest process at a time to avoid CPU contention):

      **Lint pass (parallel):** In a single message, spawn one `lint-runner` Agent call per touched workspace:
      - `lint-runner` prompt: `command: <manifest.lint>, workspace: <absolute_workspace_path>, check_type: lint`
      - If the manifest has no lint command for a workspace, still spawn `lint-runner` with `command: null` (it will return warn).

      **Test pass (serial):** For each touched workspace ONE AT A TIME (do not start the next until the current completes):
      - Collect the touched files for this workspace: the subset of changed files whose paths are under this workspace's root.
      - `test-runner` prompt: `test_command: <manifest.test>, test_affected_command: <manifest.test_affected>, touched_files: <space-separated touched file paths for this workspace>, typecheck_command: <manifest.typecheck>, workspace: <absolute_workspace_path>, check_type: test`
      - `manifest.test_affected` is the `test_affected` field from the tooling manifest — a command template with a `{files}` placeholder and `--maxWorkers=75%` baked in. May be `null` (e.g. pytest).

   4. **Auto-fix pass.** After the lint pass, check each lint-runner verdict:
      - If `counts.fixable > 0`, run the fix variant of the lint command for that workspace:
        - eslint: append `--fix` to the command
        - biome: replace `check` with `check --write`
        - ruff: replace `check` with `check --fix`
      - After auto-fix, re-spawn `lint-runner` for that workspace only (one retry).

   5. **Gate decision.** Evaluate all collected verdicts against the status enum from `contracts/runner-result-contract.md`:
      - `status: "pass"`: OK.
      - `status: "warn"`: record a coverage-deferred note in the end-of-run summary ("0 affected tests or no test command — coverage deferred to CI"). Do NOT block. Proceed.
      - `status: "fail"`: print a **Validation errors** block listing all `violations` and `failures` with `file:line` format, update task status to `blocked` in the JSON, and halt the run (same blocker logic as a TDD failure in step 6 below).
      - `status: "timeout"`: treat as a gate failure — block (same as `fail`). Note the timeout in the summary.
      - `status: "deps-missing"`: treat as a gate failure — block. Note which deps are missing.
      - When all verdicts are `pass` or `warn`: continue to browser check (if applicable) or mark done.

   **e. Browser verify (when task has `browser_verify`)**

   Only run this step if the task has a non-null `browser_verify` field. If `browser_verify` is absent or `null`, skip to step f.

   See `~/.dotfiles/claude-code-shared/resources/app-launch-detection.md` for full discovery rules.

   1. **Discover launch context** from `app-launch-detection.md`: resolve `start_command`, `base_url`, `storageState` path, and Playwright module location.

   2. **Health-check the server.** Run:
      ```bash
      curl -s -o /dev/null -w "%{http_code}" <base_url>
      ```
      - If the server responds (any 2xx or 3xx): reuse it. Record that build-code did NOT start it.
      - If no response: start the server via `start_command` using `run_in_background: true`. Poll `base_url` every 2 s until it responds, with a 60 s hard timeout. If the server never comes up, mark the task `blocked` and halt.
      - Track whether build-code started the server (boolean `server_started_by_build_code`).

   3. **Iterate (cap 3):** Maintain an iteration log. For each attempt (max 3 total):
      a. Spawn the `browser-checker` agent with: `base_url`, `url_path` (from `browser_verify.url_path`), `assertions` (from `browser_verify.assertions`), `storageState`, Playwright module location, `run_slug` (derived from task id + iteration index, e.g. `t-0023-check-1`), `cwd` (project root).
      b. Parse the JSON result per `~/.dotfiles/claude-code-shared/resources/browser-check-result.md`.
      c. **`status: "pass"`**: proceed to step f (mark done). Clean the run dir (agent already did this on success).
      d. **`status: "skipped"`**: do not block. Log `skipped_reason` in the run summary. Proceed to step f.
      e. **`status: "fail"`**: append the failing assertions and screenshot path to the iteration log. If this is not the last attempt: attempt to fix the source. If two consecutive runs produced identical failing assertions (no-progress): bail early.

   4. **On cap or no-progress bail:**
      - Tear down the server if `server_started_by_build_code` is true.
      - Print a **Browser check failed** block with: failing assertions from the final run, the iteration log, and absolute screenshot paths from `docs/browser-checks/`.
      - Update task status to `blocked` in the JSON.
      - Halt the run (same blocker logic as a TDD failure in step 6 below).

   5. **Tear down.** After a pass or skipped result: if `server_started_by_build_code` is true, kill the dev server process. Never kill a server that was already running before this task.

   **f. Mark done**
   - Update task status to `done` in the JSON.
   - Set `pr` to a suggested `gh pr create` command the user can run (do not run it).

5. **Discover follow-ups** after each successful task:
   - Review the diff produced by this task (`git diff` of changes).
   - Infer any manual follow-up actions: new env vars referenced but not provisioned, migration files created, external service configuration needed, manual testing required, etc.
   - Check `~/.dotfiles/claude-code-shared/resources/hitl-steps-runbooks.md` for matching runbooks. Use runbook steps when available. Run the runbook's `Enrichment:` instructions to gather specifics from the diff and codebase. Fill placeholders with concrete values.
   - Each follow-up step must include the exact command, exact SQL, exact config key, or exact dashboard click path. Never write a step that says "update X" or "add Y" without specifying where and how.
   - Before appending, deduplicate: compare the inferred follow-up title against existing `follow_ups` in the JSON. Skip if a similar title already exists.
   - Assign `"id"` by counting existing `follow_ups` in the file and using the next sequential `FU-XXX` (zero-padded to 3 digits).
   - Append new follow-ups to the `follow_ups` array in the JSON with `"source": "discovered"` and `"trigger_task"` set to the current task ID.
   - Write the updated JSON immediately (same write as the status update).

6. If TDD fails or gets stuck:
   - Determine if any other `not_started` task depends on this one.
     - **If yes (blocker):** update status to `blocked`, halt the run, report the failure.
     - **If no (standalone):** update status to `blocked`, continue to next task, add to end-of-run summary.

### 5. End-of-run summary

Print a status table in the conversation:

```
Run complete — docs/tasks/20260512-1423-user-auth-flow.json

 ID      Title                        Result
 ──────  ───────────────────────────  ──────────────
 T-0023  Bootstrap auth schema        done
 T-0024  Login endpoint               done
 T-0025  Design review (HITL)         parked (HITL — not blocking)
 T-0026  Token refresh flow           blocked (TDD failed)
 T-0027  Logout endpoint              skipped (blocked by T-0026)

Parked HITL tasks requiring human action:
  T-0025 — Design review: confirm token storage approach

Blocked tasks requiring investigation:
  T-0026 — Token refresh flow: TDD could not pass acceptance criteria

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
  /run-task-followups docs/tasks/<filename>   — walk through manual follow-ups interactively
  /to-e2e-tasks                               — add e2e coverage (optional, ~10-20% of changes)
```

If `follow_ups` is empty, note that in the handoff block:

```
Next steps:
  /run-task-followups   — no follow-ups found, but run to confirm
  /to-e2e-tasks         — add e2e coverage (optional)
```

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
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: build-code -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `build-code`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
**What's next:**
<!-- skill-done: build-code -->
  - `/to-e2e-tasks` — want e2e coverage for the completed changes
<!-- learning-capture:end -->
