---
name: pick
description: Rank the next ticket to pick up from the current repo's issue tracker. Reads issue_tracker and pick_buckets from repo-policy.json, shows a "Which bucket?" menu, and prints a top-5 list with copy-paste start lines. Read-only, terminal output only. Use when the user types /pick.
model: haiku
effort: low
invokedBy: human
disable-model-invocation: true
---

# Pick

Thin orchestrator: resolve repo, choose a bucket, run a fetch script, render. Strictly read-only. No writes to GitHub or Linear, no report file. All logic lives in `~/.dotfiles/claude-code-shared/scripts/pick/`.

## Process

1. Resolve the repo and its config:

   ```bash
   bash ~/.dotfiles/claude-code-shared/scripts/pick/resolve-repo.sh
   ```

   If the output is not JSON (it reads `no issue_tracker configured for <repo>`), print it verbatim and stop. This is a clean exit, not an error.

2. Otherwise parse `{repo, issue_tracker, buckets}`. If `issue_tracker` is `linear`, use `pick-fetch-linear.sh` in step 4 instead of `pick-fetch-gh.sh` (same output shape; start line uses Linear's gitBranchName). Say "sprint", never "cycle", in anything shown to the user.

3. Choose the bucket. Bare `/pick`: ask "Which bucket?" with AskUserQuestion, one option per entry in `buckets` (max 4). Free text after `/pick` is not mapped yet; if it exactly equals a bucket name, use that bucket, else show the menu.

4. Fetch, score, and render:

   ```bash
   # issue_tracker github:
   bash ~/.dotfiles/claude-code-shared/scripts/pick/pick-fetch-gh.sh "<repo>" "<bucket>" > "$TMP/cands.json"
   python3 ~/.dotfiles/claude-code-shared/scripts/pick/blockers.py resolve "$TMP/cands.json" > "$TMP/r.json" && mv "$TMP/r.json" "$TMP/cands.json"  # blocker tiers: ready, stackable (wt <branch> <base>), blocked (hidden)
   # issue_tracker linear:
   bash ~/.dotfiles/claude-code-shared/scripts/pick/pick-fetch-linear.sh "<repo>" "<bucket>" > "$TMP/cands.json"
   python3 ~/.dotfiles/claude-code-shared/scripts/pick/rank-render.py "$TMP/cands.json" --scorer-input > "$TMP/scorer-in.json"
   ```

   The fetch script emits normalized candidate JSON (shape documented in its header, checked by `validate-candidates.py`). `--scorer-input` applies the cheap pre-sort (blocked hidden, label tier) and caps the list at the top 25.

   Spawn the `pick-scorer` agent with the contents of `scorer-in.json` as its only input. Save its JSON reply to `$TMP/scores.json` and check it:

   ```bash
   python3 ~/.dotfiles/claude-code-shared/scripts/pick/validate-scorer.py output "$TMP/scores.json" --input "$TMP/scorer-in.json"
   ```

   If the reply is invalid or the agent fails, render without scores (below). Then render:

   ```bash
   python3 ~/.dotfiles/claude-code-shared/scripts/pick/rank-render.py "$TMP/cands.json" --scores "$TMP/scores.json"
   ```

   This re-ranks by effort score, prints the top 5 with a `why:` line per item and a start line `wt <branch>  ->  /grill-me <ID>` (`#N` for GitHub, Linear ID plus `gitBranchName` for Linear). Unpointed tickets show `⚠ unpointed` and are never excluded. Without `--scores` the pre-sort order is used and no `why:` lines print.

   Linear only: to apply teammate overlap, run `pick-fetch-linear-activity.sh > "$TMP/activity.json"` and add `--activity "$TMP/activity.json"` to every `rank-render.py` call (excludes tickets whose parent has a teammate active; annotates project overlap with 👥).

5. Print the script output to the terminal as-is. Do not edit, assign, label, or comment on any issue. The user starts a new session and grills the ticket manually.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `pick`.
<!-- skill-done: pick -->
<!-- learning-capture:end -->
