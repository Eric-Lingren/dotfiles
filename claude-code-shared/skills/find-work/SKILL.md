---
name: find-work
description: List spike/*, feat/*, and fix/* branches in the current repo with last commit dates. Use when user wants to find previous spikes, feature branches, fix branches, or in-progress research branches.
---

# Find Work

List all `spike/*`, `feat/*`, and `fix/*` branches in the current repo to help rediscover previous research or in-progress feature work.

## Process

1. Run the `find-work.sh` script from this skill's directory:

   ```bash
   bash "$(dirname "$0")/scripts/find-work.sh"
   ```

   The script outputs a table with branch name, last commit date, commit message, and whether a `docs/prd/` directory exists on the branch.

2. If no branches found, the script prints a message and exits.

3. Display the script output to the user.

4. If the user wants to switch to one, run `git switch {branch-name}`.
