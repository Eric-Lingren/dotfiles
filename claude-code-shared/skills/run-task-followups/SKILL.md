---
name: run-task-followups
description: Interactive walkthrough of manual follow-up actions from a tasks JSON file. Guides user through each follow-up step-by-step, offers help when stuck, and captures friction to improve templates. Use when user wants guided help completing manual follow-ups after run-tasks.
---

# Run Follow-ups

Interactive walkthrough of manual follow-ups from a `docs/tasks/` JSON file. Reads the `follow_ups` array and guides the user through each item one at a time.

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

#### a. Present the steps

Print the title and numbered steps clearly:

```
Follow-up 1 of 3: Add STRIPE_KEY to Cloudflare
Source: discovered (from T-0024)

Steps:
  1. Go to Cloudflare dashboard > Workers & Pages > your-app > Settings > Variables
  2. Click 'Add variable'
  3. Name: STRIPE_KEY, Value: from Stripe dashboard > API keys
  4. Click 'Encrypt' then 'Save'

Done? (yes / skip / help)
```

#### b. Handle user response

- **"yes" or "done"**: Mark complete, move to next.
- **"skip"**: Move to next without marking complete.
- **"help"** or any question: Assist the user. Provide additional context, clarify steps, troubleshoot issues. Stay on this follow-up until resolved.

#### c. Detect friction

If the user asks for help, reports confusion, or corrects a step, this is a friction signal. After resolving the issue, ask:

```
The steps for this type of follow-up were unclear/incorrect.
Want me to update the global templates so this is better next time? (yes / no)
```

If yes, proceed to step 4 (template update) for this item before continuing.

### 4. Update templates on friction

When the user confirms a template update:

1. Ask: "What was wrong, and what are the correct steps?"
2. Collect the corrected steps from the user.
3. Read `~/.dotfiles/claude-code-shared/skills/run-task-followups/templates.md`.
4. Check if a template for this type already exists (match by title keyword or category).
   - If exists: update the steps in place.
   - If new: append a new template entry.
5. Write the updated `templates.md`.

Template format in `templates.md`:

```markdown
## Add env var to Cloudflare

Steps:
1. Go to Cloudflare dashboard > Workers & Pages > {app-name} > Settings > Variables
2. Click 'Add variable'
3. Name: {VAR_NAME}, Value: {description of where to find the value}
4. Click 'Encrypt' then 'Save'
```

Use `{placeholder}` syntax for project-specific values. The agent fills these in when generating follow-ups.

### 5. End-of-walkthrough summary

After all follow-ups are processed, print a summary:

```
Follow-up walkthrough complete.

 #   Title                              Result
 ──   ──────────────────────────────     ──────
 1    Add STRIPE_KEY to Cloudflare       done
 2    Run database migration             done
 3    Visual test: login flow            skipped

Templates updated: 1 (Cloudflare env var steps corrected)
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
