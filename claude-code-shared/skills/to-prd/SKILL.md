---
name: to-prd
description: Turn the current conversation context into a PRD and save it to docs/prd/. Use when user wants to create a PRD from the current context.
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user — synthesize what you already know.

## Process

1. **Explore the repo** to understand the current state of the codebase, if you haven't already. Use the project's domain vocabulary (from `CONTEXT.md` and ADRs in `docs/adr/` if they exist) throughout the PRD. If neither `CONTEXT.md` nor `docs/adr/` exist, explicitly note that no project-specific vocabulary sources were found and proceed with the best domain terms available from the conversation context.

2. **Sketch the major modules** you will need to build or modify. Actively look for opportunities to extract deep modules that can be tested in isolation.

   A deep module encapsulates a lot of functionality in a simple, testable interface that rarely changes.

   Check with the user that these modules match their expectations and which ones they want tests written for.

3. **Derive a slug** from the feature name, lowercase, kebab-case, max ~40 chars (e.g. `user-auth-flow`).

4. **Ask where to write (MANDATORY).** You MUST ask before writing anything to disk. Do not skip this step:

   ```
   Where should this PRD go?
   1. Current branch
   2. New spike branch
   3. New staged branch
   ```

   If the user picks **2** or **3**:
   - Propose a branch name derived from the slug: `spike/{slug}` or `staged/{slug}`.
   - Let the user accept or type a custom name (e.g. a Linear ticket slug).
   - Run `git switch -c {branch-name}`. If the switch fails (dirty working tree), tell the user to commit or stash first and stop.
   - Continue on the new branch.

   If the user picks **1**, continue on the current branch (existing behavior).

5. **Confirm output directory (MANDATORY).** Resolve the absolute path of `docs/prd/` relative to the current working directory. Ask the user before writing:

   ```
   PRD will be saved to: /absolute/path/to/docs/prd/
   Is that correct? If not, provide the path you'd like instead.
   ```

   Use whatever path the user confirms (create it if it doesn't exist). Do not skip this step.

6. **Determine the file prefix** by running the `next-prefix.sh` script in this skill's directory: `~/.dotfiles/claude-code-shared/skills/to-prd/next-prefix.sh`. It returns a `YYYYMMDD-HHMM` timestamp prefix.

7. **Write the PRD** to `{confirmed-dir}/{prefix}-{slug}.md` (e.g. `20260511-1423-user-auth-flow.md`). Never auto-commit. Use the template from `~/.dotfiles/claude-code-shared/skills/to-prd/template.md` for the PRD structure.

8. Tell the user the path and suggest running `/to-tasks` next.
