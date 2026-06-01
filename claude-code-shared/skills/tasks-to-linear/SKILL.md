---
name: tasks-to-linear
description: Convert a docs/tasks/ JSON file into Linear tickets, preserving blocked-by relationships and writing Linear URLs back to the JSON. Use when the user wants to push tasks to Linear, create Linear issues from a task file, or sync tasks to Linear.
model: sonnet
effort: medium
---

# Tasks to Linear

Convert a `docs/tasks/` JSON file into Linear tickets. Creates one issue per task, links blocked-by relationships using real Linear issue IDs, and writes the created issue URLs back into the JSON file.

## Process

### 1. Locate the task file

List all JSON files in `docs/tasks/`. If the user provided a filename or slug as an argument, match it. Otherwise show the list and ask the user to choose. Require explicit selection — never auto-pick.

If `docs/tasks/` doesn't exist or is empty, tell the user to run `/to-tasks` first.

### 2. Parse the task file and read the PRD

Read the selected JSON file. Extract:
- `prd` path — derive the **prd-slug** by stripping the leading `NNNN-` prefix and `.md` suffix from the filename (e.g. `docs/prd/0001-shadcn-component-architecture.md` → `shadcn-component-architecture`)
- `tasks` array — the issues to create

Then read the PRD file at the `prd` path. Extract and hold in memory:
- **Problem Statement** — why this work exists
- **Solution** — the high-level approach
- **Implementation Decisions** — all phases, rules, and technical decisions
- **Out of Scope** — what is explicitly not being built

This PRD content will be embedded in every ticket description so that agents working the ticket have full context without needing to access the PRD separately.

### 3. Ask for the Linear team

Call `list_teams` and show the results. Ask the user which team to create the issues in. Require an explicit selection.

### 4. Ask for a project (optional)

Call `list_projects` filtered to the chosen team and show the results. Ask if the user wants to attach all issues to a project. Wait for the user's answer before proceeding. This is optional — if they say no or there are no relevant projects, skip it.

### 5. Ask for a status (optional)

Call `list_issue_statuses` for the chosen team and show the results. Ask the user which status to assign to all created issues. Wait for the user's answer before proceeding. This is optional — if they say no or want the Linear default, skip it.

### 6. Ask for labels (optional)

Call `list_issue_labels` for the chosen team and show the results. Ask the user which labels (if any) to apply to all created issues. Wait for the user's answer before proceeding. This is optional — if they say no, skip it.

### 7. Check for already-created issues

Scan the `tasks` array for any entries where `linear_url` is already set. If any exist, tell the user and ask whether to:
- **Skip** already-created issues and only create the missing ones
- **Recreate all** — create fresh issues for everything (does not delete old ones)

### 8. Create issues in dependency order

Sort tasks so that issues with no `blocked_by` are created first. Build a mapping of `task-id → linear-issue-id` as you go so that `blockedBy` can reference real Linear IDs.

For each task, create a Linear issue with:

**Title:** `{prd-slug}: {task title}`
Example: `shadcn-component-architecture: Directory consolidation`

**Description** (Markdown):

The description must be fully self-contained — the agent picking up this ticket will not have access to the PRD or any other file. Structure it as follows:

```
(Ticket authored by Claude Code. Scope vetted and approved by <eng-enter-name-manually>)

## Context

{Problem Statement from the PRD — why this work exists}

## Solution Overview

{Solution section from the PRD — the high-level approach and target end state}

## Relevant Implementation Details

{The specific phases, rules, classification guides, folder structures, naming conventions, and technical decisions from the PRD's Implementation Decisions section that are directly relevant to THIS task. Omit sections that are irrelevant to the task at hand. Include enough detail that the agent can make correct decisions without looking anything up.}

## Out of Scope

{Out of Scope section from the PRD, so the agent knows what not to do}

## This Task

{task description}

## Acceptance Criteria

- [ ] {criterion 1}
- [ ] {criterion 2}
…
```

**Fields to set:**
- `team` — the selected team
- `project` — the selected project, if any
- `state` — the selected status, if any
- `labels` — the selected labels, if any
- `blockedBy` — array of Linear issue IDs for any `blocked_by` task IDs, resolved from the mapping built during this run plus any existing `linear_url` entries from prior runs

**Fields to never set:** `estimate` or any complexity/story-point field — do not set these under any circumstances.

**Fields to drop from the task JSON:** `type`, `status`, `branch`, `pr`, `blocked_by` (replaced by real `blockedBy` relations)

### 9. Write Linear URLs back to the JSON file

After all issues are created, update the task JSON file: for each task, set a `linear_url` field to the created issue's URL. Write the updated JSON back to the same file path.

### 10. Report results

Print a summary table:

```
Task ID  │ Linear Issue │ Title
─────────┼──────────────┼──────────────────────────────────────────
T-0001   │ ENG-123      │ shadcn-component-architecture: Directory consolidation
T-0002   │ ENG-124      │ shadcn-component-architecture: Update Storybook story titles
…
```

Tell the user the JSON file has been updated with `linear_url` fields.
