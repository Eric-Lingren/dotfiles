---
name: to-e2e-tests
description: Analyze branch changes, discover critical user-facing workflows, grill the test plan, and generate a Playwright e2e task JSON file for run-tasks. Use when user wants to add e2e coverage after implementing a feature.
---

# To E2E Tests

Analyze the current branch's changes, discover which critical user-facing workflows are affected, stress-test the test plan with the user, and output a Playwright e2e task JSON file to `docs/tasks/` that `/run-tasks` can execute.

## Process

### 1. Detect Playwright setup

Scan the project for existing Playwright configuration:

```
find . -maxdepth 3 -name "playwright.config.*" -o -name "playwright.config.*"
```

**If config exists:** read it to learn:
- Test directory (e.g. `tests/e2e/`, `e2e/`)
- Base URL
- Project names (chromium, firefox, etc.)
- Existing fixtures, helpers, or page objects (scan the test directory)

Record these for use in task descriptions so generated tests follow existing patterns.

**If no config exists:** the first task in the output JSON will be "Scaffold Playwright setup" with acceptance criteria for config, directory structure, and a sample test. All other tasks will be blocked by this one.

### 2. Read context

Gather two sources of information:

**a. The PRD.** Look for an existing task JSON in `docs/tasks/` for the current branch. If found, read its `prd` field and load that PRD file. If multiple task files exist, ask the user which one corresponds to the current work.

If no task JSON references a PRD, ask the user to provide the PRD path or skip PRD context.

**b. The diff.** Get all changes on this branch:

```
git diff $(git merge-base HEAD origin/main)..HEAD
```

Also gather the commit log for context:

```
git log $(git merge-base HEAD origin/main)..HEAD --oneline
```

### 3. Two-pass workflow discovery

#### Pass 1: Scan for user-facing signals

Analyze the diff for changes that affect user-facing behavior:

- Route definitions or page components (new/modified)
- API endpoint handlers
- Form handlers, validation logic
- Authentication or authorization changes
- Payment, billing, or subscription logic
- Data mutations visible to users (CRUD operations)
- Navigation changes, redirects
- Error states shown to users

Ignore purely internal changes: utility refactors, type-only changes, build config, dev tooling.

#### Pass 2: Group into workflows

Cluster the signals from pass 1 into coherent user-facing workflows. Each workflow is a sequence of user actions that achieves a goal.

Examples:
- "User signup flow" (visit signup page, fill form, submit, verify email, land on dashboard)
- "Invoice creation flow" (navigate to invoices, click create, fill details, save, see confirmation)
- "Settings update flow" (open settings, change value, save, see confirmation)

### 4. Present discovered workflows

Show the user what you found. For each workflow:

- **Workflow name**: descriptive, using domain terms from CONTEXT.md if it exists
- **Signals found**: which diff changes map to this workflow
- **Proposed test scenarios**: happy path + key edge cases

```
Discovered workflows from branch changes:

1. Invoice creation flow
   Signals: new route /invoices/new, InvoiceForm component, createInvoice API handler
   Proposed tests:
   - Happy path: create invoice with valid data
   - Validation: submit with missing required fields
   - Edge: create invoice with maximum line items

2. Invoice PDF export
   Signals: new exportPdf handler, PdfPreview component
   Proposed tests:
   - Happy path: export existing invoice as PDF
   - Edge: export invoice with special characters in title
```

Ask:
- Are these the right workflows to cover?
- Any workflows missing?
- Are the test scenarios sufficient? Too many? Too few?
- Any edge cases I should add or remove?

Iterate until the user approves.

### 5. Grill the test plan

Once workflows are approved, stress-test the test plan. Apply the same rigor as `/grill-with-docs` but scoped to the test plan:

**Challenge against the glossary.** If `CONTEXT.md` exists, verify test names and descriptions use canonical domain terms. "Your test says 'checkout' but CONTEXT.md calls it 'order submission'. Which is right?"

**Sharpen fuzzy scenarios.** "You have 'test error handling' but which error? Network timeout? Validation failure? Auth expiry? Be specific."

**Probe edge cases.** Invent scenarios that test boundaries. "What happens if the user double-clicks submit? What if the session expires mid-flow? What about concurrent edits?"

**Cross-reference PRD.** If PRD mentions acceptance criteria not covered by any test scenario, surface the gap. "PRD says 'user sees error toast on failed payment' but no test covers the failed payment path."

**Cross-reference diff.** If the diff contains error handling, branching logic, or state transitions not covered by a test, flag it. "The diff shows a retry loop in the API handler. No test covers the retry path."

**Update CONTEXT.md inline** if new terms crystallize during the grill. Use the format in `~/.dotfiles/claude-code-shared/skills/grill-with-docs/CONTEXT-FORMAT.md`.

Ask questions one at a time. Provide your recommended answer for each. Iterate until the test plan is solid.

### 6. Determine task structure

After the grill, build the task list:

**First task (if page objects/fixtures needed):** "Create page objects and fixtures for {workflow names}." This task sets up reusable helpers: page object classes for pages touched across workflows, shared fixtures for auth state, test data setup, etc. Reference existing patterns found in step 1.

**Remaining tasks:** One task per test scenario. Each task:
- Is type `AFK`
- Is `blocked_by` the fixtures task only (or nothing if no fixtures task)
- Has no dependencies on other test tasks
- Includes `test_metadata` with workflow, test type, pages touched, and setup fixtures
- Has acceptance criteria describing expected test behavior

### 7. Determine the next task ID

Scan **all existing JSON files** in `docs/tasks/` and find the highest numeric suffix across every task `id` field. The first task in the new file gets that number + 1. This ensures globally unique IDs.

If `docs/tasks/` is empty or doesn't exist, start at `T-0001`.

### 8. Confirm output directory

Resolve the absolute path of `docs/tasks/` relative to the current working directory. Ask the user before writing:

```
E2E tasks file will be saved to: /absolute/path/to/docs/tasks/
Is that correct?
```

Use whatever path the user confirms. Create it if it doesn't exist.

### 9. Confirm branching strategy

**MANDATORY.** Before writing the JSON file, ask the user which branch the e2e tasks should be created on. Use `AskUserQuestion` with these options:

1. **Current branch** (`git rev-parse --abbrev-ref HEAD`). Show the actual branch name.
2. **New branch**. Ask the user for the branch name.
3. **Per-task branches**. Each task gets its own branch derived from task ID and title.

Also confirm: should the JSON file itself be saved on the current branch, or on the task branch? Default to current branch.

Set `branching.strategy` to `"single"` for options 1-2, or `"per-task"` for option 3. Set `branching.branch` to the confirmed branch name (or `null` for per-task).

### 10. Write the JSON file

Derive the slug from the PRD filename if available (strip timestamp prefix and extension). If no PRD, derive from the branch name.

Generate filename: `YYYYMMDD-HHMM-e2e-{slug}.json`.

If a file for this slug already exists (any prefix), ask whether to overwrite or merge (same logic as `/to-tasks`).

<task-json-schema>
{
  "prd": "docs/prd/YYYYMMDD-HHMM-{slug}.md (or .html, or null if no PRD)",
  "generated_at": "<ISO 8601 timestamp>",
  "source_branch": "<branch name these tests were generated from>",
  "branching": {
    "strategy": "single",
    "branch": "<current branch name>"
  },
  "tasks": [
    {
      "id": "T-0030",
      "title": "Create page objects and fixtures for invoice flow",
      "type": "AFK",
      "description": "Set up reusable Playwright page objects and fixtures for the invoice creation and export workflows. Create page objects for LoginPage, DashboardPage, InvoiceFormPage, InvoiceDetailPage. Create fixtures for authenticated user state and test organization with sample data.",
      "acceptance_criteria": [
        "Page object classes exist for each page touched by test scenarios",
        "Auth fixture creates and caches authenticated browser state",
        "Test data fixture seeds required entities",
        "A smoke test using the fixtures passes"
      ],
      "test_metadata": {
        "workflow": "shared",
        "test_type": "fixtures",
        "pages_touched": ["login", "dashboard", "invoice-form", "invoice-detail"],
        "setup_fixtures": []
      },
      "blocked_by": [],
      "status": "not_started",
      "branch": null,
      "pr": null
    },
    {
      "id": "T-0031",
      "title": "Test: create invoice with valid data",
      "type": "AFK",
      "description": "E2E test covering the happy path of invoice creation. User navigates to invoice form, fills all required fields, submits, and sees the created invoice on the detail page.",
      "acceptance_criteria": [
        "Test navigates to /invoices/new",
        "Test fills all required fields using page object methods",
        "Test submits the form and asserts redirect to invoice detail",
        "Test verifies invoice data appears correctly on detail page"
      ],
      "test_metadata": {
        "workflow": "invoice creation",
        "test_type": "e2e",
        "pages_touched": ["invoice-form", "invoice-detail"],
        "setup_fixtures": ["authenticated-user", "test-organization"]
      },
      "blocked_by": ["T-0030"],
      "status": "not_started",
      "branch": null,
      "pr": null
    }
  ],
  "follow_ups": []
}
</task-json-schema>

**Field rules (same as `/to-tasks` plus extensions):**
- `id`: globally sequential across all task files, zero-padded to 4 digits
- `type`: always `"AFK"` for e2e test tasks
- `status`: `"not_started"` | `"in_progress"` | `"done"` | `"merged"` | `"blocked"`
- `blocked_by`: fixtures task ID only, or empty for the fixtures task itself
- `branch`: `null` (single branch strategy, uses `branching.branch`)
- `pr`: `null` until merged
- `source_branch`: the branch these tests analyze (for traceability)
- `branching.strategy`: `"single"` or `"per-task"` (user-confirmed in step 9)
- `branching.branch`: user-confirmed branch name, or `null` for per-task strategy
- `test_metadata.workflow`: which user-facing workflow this test covers, or `"shared"` for fixtures
- `test_metadata.test_type`: `"fixtures"`, `"e2e"`, or `"smoke"`
- `test_metadata.pages_touched`: array of page names matching page object names
- `test_metadata.setup_fixtures`: array of fixture names this test requires

Tell the user the output path and ID range once written. Remind them to run `/run-tasks` on the file to generate the actual tests.
