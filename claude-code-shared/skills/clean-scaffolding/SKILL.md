---
name: clean-scaffolding
description: Delete all disposable doc scaffolding (seeds, PRDs, tasks, handoffs) in the current working tree. Leaves docs/adr/ and docs/prototypes/ untouched. Use when done with a workflow and ready to clear the clutter. Pass --force or -y to skip the confirmation prompt.
argument-hint: "--force or -y to skip confirmation"
model: haiku
effort: low
---

Delete all disposable scaffolding artifacts from `docs/` in the current working directory.

A single script does the enumeration, the listing, and the deletion, so the behavior is identical on every run. Your only job is to run it and gate the destructive step behind confirmation. **Do not enumerate, list, or delete files yourself.** Do not run `find`, `ls`, `rm`, `rmdir`, or git. Use only the two script invocations below.

The script (`~/.dotfiles/claude-code-shared/skills/clean-scaffolding/scripts/clean-scaffolding.sh`) deletes files in these dirs, relative to cwd: all files in `docs/seeds/`, `docs/prd/`, `docs/tasks/`, and `.md` files only in `docs/handoffs/`. It never touches `docs/adr/` or `docs/prototypes/`, and it removes any dir left empty afterward (including `docs/` itself). If the script is not found at that path, stop and tell the user. Do not guess another path.

## Process

### 1. Parse args

If args include `--force` or `-y`, set `skip_confirm = true`. Otherwise `skip_confirm = false`.

### 2. Preview (ALWAYS run this first)

Run:

```bash
bash ~/.dotfiles/claude-code-shared/skills/clean-scaffolding/scripts/clean-scaffolding.sh preview
```

This prints the full grouped file list and a total to the terminal, which the user sees directly. You must run this on every invocation, including when `skip_confirm` is true. The file count comes only from this output. Never state or confirm a count you did not get from a preview run you just executed.

- Exit code 2 (output `Nothing to clean.`): report `Nothing to clean.` and stop. Do not run delete.
- Exit code 0: read the `Total: N files` line. That `N` is the count for the confirmation prompt.

### 3. Confirm

If `skip_confirm` is false, call `AskUserQuestion`:

- Question: `Delete N files? This cannot be undone in repos where these files are untracked.` (use the `N` from the preview)
- Options: `Yes, delete all` / `No, cancel`

Stop if the user cancels. If `skip_confirm` is true, skip this step.

### 4. Delete

Run:

```bash
bash ~/.dotfiles/claude-code-shared/skills/clean-scaffolding/scripts/clean-scaffolding.sh delete
```

This re-enumerates the same set, removes each file with an explicit per-path `rm` (printing each one), and removes any now-empty dirs. It prints `Deleted N files.` when done.

### 5. Report

Relay the script's `removed ...` lines and `Deleted N files.` summary. Keep it short.
