---
name: to-prd
description: Turn the current conversation context into a PRD and save it to docs/prd/. Use when user wants to create a PRD from the current context.
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user — synthesize what you already know.

## Process

1. **Explore the repo** to understand the current state of the codebase, if you haven't already. Use the project's domain vocabulary (from `CONTEXT.md` and ADRs in `docs/adr/` if they exist) throughout the PRD.

2. **Sketch the major modules** you will need to build or modify. Actively look for opportunities to extract deep modules that can be tested in isolation.

   A deep module encapsulates a lot of functionality in a simple, testable interface that rarely changes.

   Check with the user that these modules match their expectations and which ones they want tests written for.

3. **Derive a slug** from the feature name — lowercase, kebab-case, max ~40 chars (e.g. `user-auth-flow`).

4. **Determine the file prefix** by scanning `docs/prd/` for files matching the pattern `NNNN-*.md` and taking the highest existing number + 1, zero-padded to 4 digits. If the directory is empty or doesn't exist, start at `0001`.

5. **Write the PRD** to `docs/prd/{prefix}-{slug}.md` (e.g. `0001-user-auth-flow.md`). Create `docs/prd/` if it doesn't exist.

6. Tell the user the path and suggest running `/to-tasks` next.

<prd-template>

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A numbered list of user stories. Each in the format:

1. As a `<actor>`, I want `<feature>`, so that `<benefit>`

This list should be extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions:

- The modules that will be built/modified
- The interfaces of those modules
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets — they go stale quickly.

## Testing Decisions

- What makes a good test for this feature (test external behavior, not implementation details)
- Which modules will be tested
- Prior art in the codebase (similar test patterns to follow)

## Out of Scope

What is explicitly not being built in this PRD.

## Further Notes

Any additional context.

</prd-template>
