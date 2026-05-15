---
name: run-tasks
description: Execute tasks from a tasks JSON file sequentially using TDD. Handles branching, status updates, blocker detection, and HITL pausing. Use when user wants to run AI tasks from a docs/tasks/ file.
---

# Run Tasks

Execute tasks from a `docs/tasks/` JSON file sequentially, using `/tdd` for each AFK task. Updates task status in the JSON as work progresses.

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

If `type` is `"HITL"`:
- Determine if any other `not_started` task in the queue depends on this task.
  - **If yes (it is a blocker):** update status to `in_progress` in the JSON, print the task's title, description, and acceptance criteria, tell the user this requires human action, and halt the run.
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

## PRD context

{full contents of the PRD file}
```

4. If TDD completes successfully:
   - Update task status to `done` in the JSON.
   - Set `pr` to a suggested `gh pr create` command the user can run (do not run it).

5. **Discover follow-ups** after each successful task:
   - Review the diff produced by this task (`git diff` of changes).
   - Infer any manual follow-up actions: new env vars referenced but not provisioned, migration files created, external service configuration needed, manual testing required, etc.
   - Check `~/.dotfiles/claude-code-shared/skills/run-followups/templates.md` for matching templates. Use template steps when available. Fill in project-specific values.
   - Before appending, deduplicate: compare the inferred follow-up title against existing `follow_ups` in the JSON. Skip if a similar title already exists.
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

Run `/run-followups` for interactive walkthrough with step-by-step guidance.
```

Do not write this summary to any file.

### 6. Offer follow-up walkthrough

If the `follow_ups` array in the JSON is non-empty, print:

```
Run `/run-followups` to walk through manual follow-ups interactively.
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

1. Run `git push -u origin HEAD` to push the branch.
2. Run `gh pr create --title "<title>" --body "<description>"` using the generated title and body.
3. Return the PR URL to the user.
