---
name: find-work
description: List spike/* and staged/* branches in the current repo with last commit dates. Use when user wants to find previous spikes, staged work, or in-progress research branches.
---

# Find Work

List all `spike/*` and `staged/*` branches in the current repo to help rediscover previous research or staged feature work.

## Process

1. Run `git branch --list "spike/*" "staged/*"` to find work branches.

2. If no branches found, tell the user "No spike or staged branches in this repo."

3. For each branch found, gather:
   - Branch name
   - Last commit date and message: `git log -1 --format="%ai %s" {branch}`
   - Whether it has a `docs/prd/` directory: `git ls-tree {branch} docs/prd/ 2>/dev/null`

4. Display as a table:

   ```
   Branch                        Last commit                    PRD
   spike/user-auth-flow          2026-05-07  add PRD            yes
   staged/billing-refactor       2026-04-20  add tasks          yes
   spike/search-exploration      2026-03-15  notes              no
   ```

5. If the user wants to switch to one, run `git switch {branch-name}`.
