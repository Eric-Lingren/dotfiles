---
name: to-tasks
description: Break a PRD into independently-grabbable tasks using tracer-bullet vertical slices, then write a JSON task file to docs/tasks/. Use when user wants to convert a PRD into AI-ready tasks.
model: sonnet
effort: high
---

# To Tasks

Break a PRD into independently-grabbable tasks using vertical slices (tracer bullets) and write the result as a JSON file to `docs/tasks/`.

## Contract

**Consumes:** seed file OR HTML PRD — see `contracts/seed-contract.md` (schema_version: `"4"`)
**Produces:** task file — see `contracts/task-contract.md` (schema_version: `"1"`)

When input is a seed file (`.json`), apply Step-0a directly. When input is an HTML PRD (`.html` or `.md`), run `scripts/extract-prd-json.sh <path>` first to extract the embedded seed JSON, then apply Step-0a on the extracted JSON.

**Step-0a — validate seed input before processing:**
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  --instance ~/.dotfiles/claude-code-shared/contracts/seed-schema.json \
  <seed-path-or-extracted-json>
```

Gate is deterministic:
- Exit 0: proceed.
- Non-zero exit: STOP. Report the stderr output to the user verbatim. Do not process the seed.
- If validate-schema.sh itself errors or is not found: STOP. Report the error to the user. Do not improvise alternate validation.

**Step-0b — validate task output after writing:**
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  --instance ~/.dotfiles/claude-code-shared/contracts/task-schema.json \
  <output-path>
```
On non-zero exit: STOP. Report stderr to the user. Do not write the file.

## Process

### 1. Locate the source artifact

If a path argument was passed (e.g. `/to-tasks docs/seeds/20260602-1234-my-feature.json`), use it directly — skip discovery.

Otherwise, list all available source files and ask the user to choose. Never auto-pick:
- `docs/prd/*.html` and `docs/prd/*.md` — HTML and markdown PRDs
- `docs/seeds/*.json` — seed files from `/to-seed`

Show all files found across both directories as a numbered list.

Route the path through resolve-ref.sh before reading (see `resources/resolve-ref-pattern.md`): Run `bash ~/.dotfiles/claude-code-shared/scripts/resolve-ref.sh $(basename <path>)`. On archive hit (output starts with `ARCHIVE:`), use the extracted content in place of the file. On not-found (exit non-zero), surface the diagnostic and ask "Continue anyway?" — bypass rebuilds context from conversation.

Run `~/.dotfiles/claude-code-shared/skills/to-tasks/scripts/extract-prd-json.sh <path>` on the selected file to extract and validate the JSON. Use that output as the primary source. Do NOT use inline python or other ad-hoc extraction. The script handles `.html`, `.md`, and `.json` files.

If neither `docs/prd/` nor `docs/seeds/` exists or both are empty on the current branch:
- Run `git branch --list "spike/*" "feat/*" "fix/*"` to check for work branches.
- If work branches exist, tell the user: "No source artifacts found on this branch. These work branches exist:" and list them. Ask if they want to switch to one.
- If the user picks a branch, run `git switch {branch-name}` and re-list both directories.
- If no work branches exist either, tell the user to run `/to-seed` or `/to-prd-html` first.

**Hard refusal for draft seeds:** If the source is a seed JSON, read its `status` field. If `status` is `"draft"` (open_threads non-empty), stop immediately:

```
ERROR: This seed is in draft status — open_threads is non-empty.
Open threads: [<list them>]

to-tasks hard-refuses a draft seed. All judgment threads must be resolved before
task generation. Run /to-seed <handoff-path> to merge resolutions, or run /grill-me
to resolve the threads in a new session.
```

Do not generate any tasks. Do not ask clarifying questions. Stop.

**Quality-gate override for degraded seeds (v4 only):** After confirming `status` is `"ready"`, check whether `schema_version` is `"4"`. If it is, read the `verification` field. If `verification.status` is `"degraded"`, show the following and ask the user to confirm (one-click confirm, not a type-confirm):

```
Quality gate: this seed has verification.status: 'degraded'.
The adversary panel did not complete — one or more persona or judge agents failed
during the to-seed verification stage.

Generating tasks from an unverified seed carries risk: fabrications or omissions
in the seed may not have been caught.

Confirm to override this gate and generate tasks anyway, or cancel to re-run /to-seed.
```

- If the user confirms: proceed. Record the override in the tasks artifact as `gate_override: {gate: "quality", reason: "user confirmed override of degraded verification.status", confirmed_at: "<ISO 8601 timestamp>"}`. **Do not flip the seed's verification.status to 'verified'.** The seed stays honestly degraded.
- If the user cancels: stop. Do not generate any tasks.

**Note:** a sanctioned override never launders the seed. The seed's `verification.status` field must not be changed to `"verified"` as a side effect of generating tasks.

**Structural-gate override for schema-invalid seeds:** If Step-0a exits non-zero (schema validation failed), show the exact validation errors from stderr, then ask the user to type-confirm to override:

```
Structural gate: seed schema validation failed.
Errors:
  <exact stderr output from validate-schema.sh>

Type "override" to generate tasks anyway (risky — schema errors may cause downstream failures),
or press Enter to cancel.
```

- If the user types "override": proceed. Record the override as `gate_override: {gate: "structural", reason: "user typed override despite schema validation errors: <first error line>", confirmed_at: "<ISO 8601 timestamp>"}`.
- If the user does not type "override": stop.

Seeds with `verification.status: "verified"` proceed normally with no gate prompt.
Seeds without a `verification` field (schema_version "3" and earlier) proceed without this check for backward compatibility.

Record the source type and path for provenance stamping:
- Seed JSON file → `source = {"type": "seed", "ref": "<file-path>"}`
- HTML/MD PRD file → `source = {"type": "prd", "ref": "<file-path>"}`

### 2. Load project context

Spawn the `context-loader` agent (`subagent_type: context-loader`, repo root as working directory). It returns `vocabulary` (domain terms, inlined) and `adrs` (one-line decisions + paths). Use `vocabulary` terms in task titles and descriptions. If the payload's `missing` list is non-empty, proceed with terms from the conversation context.

### 3. Draft vertical slices

Break the PRD into **tracer bullet** tasks. Each task is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be **HITL** (requires a keyboard action the AI cannot perform AFK — e.g. enable a feature flag, add a credential to a secrets manager, configure DNS, seed production data, click a third-party dashboard button) or **AFK** (can be implemented and merged without human interaction). Prefer AFK over HITL where possible.

**HITL means hands-only.** Decisions that change what gets built are resolved in the grill and become `decisions[]` in the seed — they never become tasks. A task that says "decide the architecture" or "design review" is NOT a valid HITL task.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- Every slice MUST include tests, whether it is new code, a refactor, or a move
- For refactoring slices: the description must state that characterization tests for existing behavior are written BEFORE any restructuring begins. If the code being refactored has no test coverage, the first step is capturing current behavior in tests. Then refactor while keeping tests green.
- **out_of_scope guard:** If the PRD has an `out_of_scope[]` field, read it. Never generate a task slice for any item listed there — skip it silently. The rationale in each out_of_scope entry is negative context: use it to avoid accidentally implementing a rejected thing under a different name.
</vertical-slice-rules>

#### browser_verify field

For user-facing feature and fix tasks (route or UI changes), populate `browser_verify` using PRD intent. Schema: `~/.dotfiles/claude-code-shared/contracts/task-schema.json`.

- `url_path`: the route the feature lives on (e.g. `/dashboard`, `/settings/billing`).
- `assertions`: **concrete observable behaviors** — visible text, navigation targets, redirects. Not vague prose ("works correctly" is invalid; "Text 'Welcome back' is visible in the heading" is valid).
- **Omit `browser_verify` entirely** (never set to `null`) for backend, config, refactor, infra, or any task with no user-visible route change.
- E2e-authoring tasks from `to-e2e-tasks` must **never** carry `browser_verify`.

**Dynamic routes:** Write variable segments as `:param` placeholders. Never invent a concrete slug — a made-up value navigates to a 404.

- Mark dynamic parts with a leading colon: `/firms/:firmSlug/dashboard`, `/reports/:reportId`.
- Placeholder names are cosmetic; the browser-checker resolves by position. Use whatever reads clearly.
- Write static segments concretely. Only variable parts get a colon.
- Never resolve placeholders yourself. See `~/.dotfiles/claude-code-shared/agents/browser-checker.md`.

#### Auth-gated routes

Before finalizing tasks for any auth-gated route, check for a storageState file using the discovery order in `~/.dotfiles/claude-code-shared/resources/app-launch-detection.md` (step 3: storageState path).

- **storageState found**: include `browser_verify` normally. browser-checker loads the existing auth state.
- **storageState NOT found**: do NOT omit `browser_verify`. Instead:
  1. Insert a prerequisite task titled "Generate Playwright auth state" (type: AFK) as the first task in the graph. Its description must specify: run headless login flow, save output to `playwright/.auth/user.json` via `page.context().storageState({ path })`.
  2. All auth-gated `browser_verify` tasks must list this setup task in their `blocked_by`.
  3. Note this during task output: "No storageState found. A setup task was added to generate auth state before browser verification can run."

Never skip `browser_verify` on an auth-gated route without first checking for storageState. "Route is auth-gated" is not a valid reason to omit verification.

### 3a. Capture deferred[] items as triage tasks

After emitting build tasks, scan `deferred[]` from the seed. If `deferred[]` is empty or absent, skip this section and produce no triage tasks.

For each item in `deferred[]`, emit one triage task:

- **title**: first sentence of `deferred.text` (up to the first `.` or end of string)
- **description**: full `deferred.text`. Append `deferred.context` on a new paragraph if present.
- **type**: `AFK` (triage tasks are routed mechanically, no keyboard action required)
- **task_type**: `triage`
- **domain**: resolve from `~/.dotfiles/claude-code-shared/resources/repo-policy.json` using the current repo. Run `git remote get-url origin`, normalize to `Org/Repo` format (strip protocol/host, remove `.git` suffix), look up the `domain` field on that entry. Default to `"personal"` if the repo is not found.
- **deliverable**: classify by what the item produces. Use `"code"` when the item describes building, implementing, extending, or modifying software, skills, agents, scripts, adapters, schemas, or any other code artifact — even if the words "PR" or "code change" do not appear literally. Use `"non-code"` only for items that genuinely produce no code output: research, reading lists, process planning, documentation, or organizational notes.
- **acceptance_criteria**: a single string: `"Item has been exported to its destination by export-tasks"`.
- **blocked_by**: `[]` unless `deferred.context` explicitly names a dependency on a code task ID (`T-XXXX`) in the same file.
- **status**: `not_started`
- **branch**: `null`
- **pr**: `null`
- **seed_ref**: seed filename basename only (e.g. `20260606-1550-foo.json`, no directory prefix). Derive with `basename(seed_path)`.
- **task_ref**: output task file filename basename only (e.g. `20260606-1601-foo.json`, no directory prefix). Use the filename produced by `task-filename.sh` in step 6.

Omit `browser_verify` and `linear_url` for triage tasks. Do not emit triage tasks for items in `out_of_scope[]` or `disposed_threads[]`.

Append triage tasks after all build tasks in the `tasks[]` array.

### 3b. Infer follow-ups from the source artifact

Scan the source artifact for manual actions outside the task graph: env var provisioning, DNS config, external service setup, database migrations, manual testing, deployment steps, credential rotation, etc.

Draft a `follow_ups` list. Each item has:
- **title**: what needs doing
- **steps**: ordered, specific instructions. Each step must include the exact command, exact SQL, exact config key, or exact dashboard click path. Never write a step that says "update X" or "add Y" without specifying where and how.
- **trigger_task**: which task ID creates the need, or `null` if general
- **source**: `"planned"`

Check `~/.dotfiles/claude-code-shared/resources/hitl-steps-runbooks.md` for existing runbooks that match. Use runbook steps when available. Run the runbook's `Enrichment:` instructions to gather project-specific values from the codebase. Fill placeholders with concrete values.

### 4. Determine the next task ID

Run `~/.dotfiles/claude-code-shared/scripts/next-task-id.sh docs/tasks/` to get the next available ID. The script scans all JSON files in the directory and returns the next globally unique ID.

### 5. Derive branch name

Always use `strategy: "single"`. Never ask the user to choose between single and per-task.

Ask only: "Branch name?" — use the naming conventions in `~/.dotfiles/claude-code-shared/resources/branching-strategy.md` to suggest a default (derive from current branch prefix + slug). User can accept or override.

Record in the JSON: `{"strategy": "single", "branch": "{confirmed-name}"}`.

### 6. Write the JSON file

Derive the slug from the source artifact filename by stripping the leading timestamp prefix and extension (e.g. `20260511-1423-user-auth-flow.json` → slug `user-auth-flow`). The timestamp prefix format is `YYYYMMDD-HHMM-`.

Run `~/.dotfiles/claude-code-shared/scripts/task-filename.sh <slug>` to generate the filename. Write to `docs/tasks/<filename>` (create the directory if it doesn't exist).

If a file for this slug already exists (any prefix), ask the user whether to:
- **Overwrite** — replace the file entirely with the new breakdown (re-scan all other files to find the next task ID, excluding this file; keep the existing filename prefix)
- **Merge** — keep existing task statuses/PRs and add/update task definitions (new tasks continue from the current global max; keep the existing filename prefix)

Read the canonical schema now:
```bash
cat ~/.dotfiles/claude-code-shared/contracts/task-schema.json
```
Use that schema exactly. Do not guess field names or structure.

Set `"producer": "to-tasks"`.

Set `source.ref` to the seed filename basename only (e.g. `"20260606-1550-foo.json"`), not a relative or absolute path. Strip the directory prefix when writing this field.

After writing, output a single line:

```
docs created here: docs/tasks/<filename>
```

Run `python3 ~/.dotfiles/claude-code-shared/scripts/print-skill-next-steps.py to-tasks` and print the output as the closing suggestion. Output text like:

```
docs created here: docs/tasks/<filename>

Next steps:
<script output>
```

<!-- learning-capture:start -->
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: to-tasks -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `to-tasks`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
**What's next:**
<!-- skill-done: to-tasks -->
  - `/dispatch-tasks` — tasks are ready to execute
<!-- learning-capture:end -->
