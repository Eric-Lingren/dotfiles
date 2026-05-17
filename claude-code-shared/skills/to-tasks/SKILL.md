---
name: to-tasks
description: Break a PRD into independently-grabbable tasks using tracer-bullet vertical slices, then write a JSON task file to docs/tasks/. Use when user wants to convert a PRD into AI-ready tasks.
---

# To Tasks

Break a PRD into independently-grabbable tasks using vertical slices (tracer bullets) and write the result as a JSON file to `docs/tasks/`.

## Process

### 1. Locate the PRD

Always ask the user to provide the PRD file path. List the available files in `docs/prd/` (both `.md` and `.html`) so they can choose, but require an explicit selection. Never auto-pick.

**HTML PRDs:** If the selected file is `.html`, run `~/.dotfiles/claude-code-shared/skills/to-tasks/scripts/extract-prd-json.sh <path>` to extract the embedded JSON. Use that output as the primary source for user stories, implementation decisions, and testing decisions. Do NOT use inline python or other ad-hoc extraction. The script handles both `.md` and `.html` files.

If `docs/prd/` doesn't exist or is empty on the current branch:
- Run `git branch --list "spike/*" "feat/*" "fix/*"` to check for work branches.
- If work branches exist, tell the user: "No PRDs found on this branch. These work branches exist:" and list them. Ask if they want to switch to one.
- If the user picks a branch, run `git switch {branch-name}` and re-list `docs/prd/`.
- If no work branches exist either, tell the user to run `/to-prd` first.

### 2. Explore the codebase (optional)

If you haven't already explored the codebase in this session, do a light exploration to understand the current state. Task titles and descriptions should use the project's domain vocabulary.

### 3. Draft vertical slices

Break the PRD into **tracer bullet** tasks. Each task is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be **HITL** (requires human interaction — architectural decision, design review) or **AFK** (can be implemented and merged without human interaction). Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- Every slice MUST include tests, whether it is new code, a refactor, or a move
- For refactoring slices: the description must state that characterization tests for existing behavior are written BEFORE any restructuring begins. If the code being refactored has no test coverage, the first step is capturing current behavior in tests. Then refactor while keeping tests green.
</vertical-slice-rules>

### 3b. Infer follow-ups from the PRD

Scan the PRD for manual actions outside the task graph: env var provisioning, DNS config, external service setup, database migrations, manual testing, deployment steps, credential rotation, etc.

Draft a `follow_ups` list. Each item has:
- **title**: what needs doing
- **steps**: ordered, specific instructions. Each step must include the exact command, exact SQL, exact config key, or exact dashboard click path. Never write a step that says "update X" or "add Y" without specifying where and how.
- **trigger_task**: which task ID creates the need, or `null` if general
- **source**: `"planned"`

Check `~/.dotfiles/claude-code-shared/resources/hitl-steps-runbooks.md` for existing runbooks that match. Use runbook steps when available. Run the runbook's `Enrichment:` instructions to gather project-specific values from the codebase. Fill placeholders with concrete values.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices must complete first (by number)
- **User stories covered**: which user stories from the PRD this addresses

Then present inferred follow-ups as a separate list. For each follow-up show:
- **Title**: what manual action is needed
- **Trigger task**: which task creates the need (or "general")
- **Steps**: the step-by-step instructions

Ask:
- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL vs AFK?
- Are the follow-ups correct? Any missing? Any unnecessary?

Iterate until the user approves the breakdown.

### 5. Determine the next task ID

Before assigning IDs, scan **all existing JSON files** in `docs/tasks/` and find the highest numeric suffix across every task `id` field in every file. The first task in the new file gets that number + 1. This ensures IDs are globally unique across all task files in the repo and agents never confuse tasks from different PRDs.

Example: if `docs/tasks/auth.json` contains tasks up to `T-014` and `docs/tasks/search.json` up to `T-022`, the next file starts at `T-023`.

If `docs/tasks/` is empty or doesn't exist yet, start at `T-0001`.

### 6. Ask about branching strategy

Before writing the file, ask the user which branching strategy they want for this task file:

- **One branch / one PR for all tasks** — the user provides a branch name; all tasks share it (e.g. contributing micro-work to a single feature branch)
- **One branch / one PR per task** — the skill generates a branch name per task from the `branch` field

Record the answer in the `branching` field of the JSON.

### 7. Confirm output directory (MANDATORY)

Resolve the absolute path of `docs/tasks/` relative to the current working directory. Ask the user before writing:

```
Tasks file will be saved to: /absolute/path/to/docs/tasks/
Is that correct? If not, provide the path you'd like instead.
```

Use whatever path the user confirms (create it if it doesn't exist). Do not skip this step.

### 8. Write the JSON file

Derive the slug from the PRD filename by stripping the leading timestamp prefix and extension (e.g. `20260511-1423-user-auth-flow.md` → slug `user-auth-flow`, or `20260511-1423-user-auth-flow.html` → slug `user-auth-flow`). The timestamp prefix format is `YYYYMMDD-HHMM-`.

Generate the file prefix as a `YYYYMMDD-HHMM` timestamp (current time). Write to `{confirmed-dir}/{prefix}-{slug}.json`.

If a file for this slug already exists (any prefix), ask the user whether to:
- **Overwrite** — replace the file entirely with the new breakdown (re-scan all other files to find the next task ID, excluding this file; keep the existing filename prefix)
- **Merge** — keep existing task statuses/PRs and add/update task definitions (new tasks continue from the current global max; keep the existing filename prefix)

<task-json-schema>
{
  "prd": "docs/prd/YYYYMMDD-HHMM-{slug}.md (or .html)",
  "generated_at": "<ISO 8601 timestamp>",
  "branching": {
    "strategy": "single",
    "branch": "feat/my-feature"
  },
  "tasks": [
    {
      "id": "T-023",
      "title": "Short descriptive title",
      "type": "AFK",
      "description": "End-to-end behavior description, not layer-by-layer implementation. For refactor tasks: state that characterization tests must be written for existing behavior before restructuring begins.",
      "acceptance_criteria": [
        "Criterion 1 (always include test-related criteria)",
        "Criterion 2"
      ],
      "blocked_by": [],
      "status": "not_started",
      "branch": "feat/t-023-short-title",
      "pr": null
    }
  ],
  "follow_ups": [
    {
      "title": "Add STRIPE_KEY to Cloudflare",
      "steps": [
        "Go to Cloudflare dashboard > Workers & Pages > your-app > Settings > Variables",
        "Click 'Add variable'",
        "Name: STRIPE_KEY, Value: from Stripe dashboard > API keys",
        "Click 'Encrypt' then 'Save'"
      ],
      "trigger_task": "T-0024",
      "source": "planned"
    }
  ]
}
</task-json-schema>

**Field rules:**
- `id`: globally sequential across all task files, zero-padded to 4 digits (`T-0001`, `T-0002`, …)
- `type`: `"AFK"` or `"HITL"`
- `status`: `"not_started"` | `"in_progress"` | `"done"` | `"merged"` | `"blocked"`
- `blocked_by`: array of `id` strings (e.g. `["T-0023"]`), empty if none
- `branch`: `{prefix}/t-{id-number}-{kebab-title}`, lowercase, max ~40 chars total. Only used when `branching.strategy` is `"per-task"`. Derive `{prefix}` from the current branch name (`feat/`, `fix/`, or `spike/`). If the current branch has no recognized prefix (e.g. `main`), ask the user whether this is a `feat` or `fix`.
- `pr`: `null` until merged; then PR URL or number as a string
- `branching.strategy`: `"single"` (one shared branch, user-provided) or `"per-task"` (auto-generated per task)
- `branching.branch`: only present when `strategy` is `"single"`

**Follow-up field rules:**
- `follow_ups`: top-level array, sibling to `tasks`
- `title`: short description of the manual action
- `steps`: ordered array of specific instructions. Use platform-specific click paths when known.
- `trigger_task`: task ID string (e.g. `"T-0024"`) or `null` if general
- `source`: `"planned"` (from PRD) or `"discovered"` (found during `run-tasks`)

Tell the user the output path and the ID range used (e.g. `T-0023 – T-0031`) once written.
