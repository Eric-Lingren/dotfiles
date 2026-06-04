---
name: run-task-followups
description: Interactive walkthrough of manual follow-up actions from a tasks JSON file. Guides user through each follow-up step-by-step, enriches steps with codebase context, offers help when stuck, and captures friction to improve shared runbooks. Use when user wants guided help completing manual follow-ups after run-tasks.
model: sonnet
effort: medium
---

# Run Follow-ups

Interactive walkthrough of manual follow-ups from a `docs/tasks/` JSON file. Reads the `follow_ups` array and guides the user through each item one at a time.

## Contract

**Format:** task file — see `contracts/task-contract.md` (schema_version: `"1"`)
**Role:** consumer

**Step-0 — validate input before processing:**
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  ~/.dotfiles/claude-code-shared/contracts/task-schema.json \
  <input-path>
```
On non-zero exit: STOP. Report stderr to the user. Do not process the file.

## Process

### 1. Ask for task file

List ALL `*.json` files in `docs/tasks/`. Present as numbered options. Ask the user to pick one.

Read the chosen JSON file. If `follow_ups` is empty or missing, tell the user there are no follow-ups and exit.

### 2. Present the follow-up queue

Print a numbered summary of all follow-ups:

```
Follow-ups for: docs/tasks/20260512-1423-user-auth-flow.json

 #   Title                              Source     Trigger
 ──   ──────────────────────────────     ────────   ───────
 1    Add STRIPE_KEY to Cloudflare       discovered T-0024
 2    Run database migration             planned    T-0023
 3    Visual test: login flow            planned    T-0024

Starting from #1. Say "skip" to jump to the next item.
```

### 3. Walk through each follow-up

For each follow-up in order:

#### a. Enrich steps before presenting

Before showing the follow-up to the user, enrich its steps:

1. Read `~/.dotfiles/claude-code-shared/resources/hitl-steps-runbooks.md`.
2. Find a matching template by title keyword or category.
   - **If matched:** run the template's `Enrichment:` instructions. Grep the codebase, read config files, check diffs. Replace vague steps with specific values found.
   - **If no match:** run generic enrichment. Grep the codebase for keywords from the follow-up title. Surface relevant file paths, env var names, config keys, table/column names. Replace any step that says "update X" or "add Y" with the exact command, SQL, or dashboard path.
3. Every step must pass the quality bar from hitl-steps-runbooks.md. If a step still says "update X" without specifying where and how, rewrite it with the best info available from the codebase.

#### b. Present the enriched steps

Print the title and numbered steps clearly:

```
Follow-up 1 of 3: Add STRIPE_KEY to Cloudflare
Source: discovered (from T-0024)

Steps:
  1. Go to Cloudflare dashboard > Workers & Pages > your-app > Settings > Variables
  2. Click 'Add variable'
  3. Name: STRIPE_KEY, Value: from Stripe dashboard > API keys > Secret key (sk_live_...)
  4. Click 'Encrypt' then 'Save'

Done? (yes / skip / help)
```

#### c. Handle user response

- **"yes" or "done"**: Mark complete, move to next.
- **"skip"**: Move to next without marking complete.
- **"help"** or any question: Assist the user. Provide additional context, clarify steps, troubleshoot issues. Stay on this follow-up until resolved.

#### d. Detect friction

If the user asks for help, reports confusion, or corrects a step, this is a friction signal. After resolving the issue, ask:

```
The steps for this type of follow-up were unclear/incorrect.
Want me to update the shared runbooks so this is better next time? (yes / no)
```

If yes, proceed to step 4 (template update) for this item before continuing.

#### e. Offer template creation for unmatched follow-ups

If no template matched this follow-up (step 3a used generic enrichment), offer after the user completes it:

```
No template exists for this type of follow-up.
Want me to create one so future follow-ups like this are more specific? (yes / no)
```

If yes, proceed to step 4 to create a new runbook with an `Enrichment:` section.

### 4. Update runbooks on friction

When the user confirms a runbook update:

1. Ask: "What was wrong, and what are the correct steps?"
2. Collect the corrected steps from the user.
3. Read `~/.dotfiles/claude-code-shared/resources/hitl-steps-runbooks.md`.
4. Check if a runbook for this type already exists (match by title keyword or category).
   - If exists: update the steps and enrichment in place.
   - If new: append a new runbook entry with Steps, Notes (if needed), and Enrichment sections.
5. Write the updated `hitl-steps-runbooks.md`.

Runbook format (see `~/.dotfiles/claude-code-shared/resources/hitl-steps-runbooks.md` for examples):

```markdown
## Short title for the action

Steps:
1. Exact command or dashboard path
2. Next step with concrete values

Enrichment:
- What to grep/check in codebase to fill placeholders
```

Use `{placeholder}` syntax for project-specific values. Include an `Enrichment:` section with lookup instructions.

### 5. End-of-walkthrough summary

After all follow-ups are processed, print a summary:

```
Follow-up walkthrough complete.

 #   Title                              Result
 ──   ──────────────────────────────     ──────
 1    Add STRIPE_KEY to Cloudflare       done
 2    Run database migration             done
 3    Visual test: login flow            skipped

Runbooks updated: 1 (Cloudflare env var steps corrected)
```

### 6. Offer to push and open a PR

After the summary, ask the user: **"Push and open a PR?"**

If yes:

#### a. Generate a PR description

Gather context:
- Current branch: `git rev-parse --abbrev-ref HEAD`
- Commits on branch: `git log main...HEAD --oneline`
- Diff (truncated to first 300 lines): `git diff main...HEAD | head -n 300`
- Linear ticket: extract the first `[A-Za-z]+-[0-9]+` pattern from the branch name (uppercase). Optional. If found, check CLAUDE.md or `.claude/` config for a Linear workspace URL. If present, include `Linear Ticket: [TICKET](<workspace-url>/issue/TICKET)`. If no workspace URL, include ticket ID as plain text. If no ticket pattern, omit.

Write the PR description:

```
### <short descriptive title>
<Linear ticket link, if found>

<2-3 sentences: what was broken or missing, and what this PR does to fix it>

**Changes:**
<bullet list of key code changes, skip test files unless they are the point>
```

Rules:
- Under 250 words
- No Testing section, no other sections
- No em dashes. Use periods or commas only.
- Concise, no run-on sentences

#### b. Push and create the PR

1. Run `git push -u origin HEAD`.
2. Run `gh pr create --title "<title>" --body "<description>"`.
3. Return the PR URL to the user.
