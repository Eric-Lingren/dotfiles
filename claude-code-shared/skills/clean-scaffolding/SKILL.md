---
name: clean-scaffolding
description: Delete all disposable doc scaffolding (seeds, PRDs, tasks, handoffs) in the current working tree. Leaves docs/adr/ and docs/prototypes/ untouched. Use when done with a workflow and ready to clear the clutter. Pass --force or -y to skip the confirmation prompt.
argument-hint: "--force or -y to skip confirmation"
model: haiku
effort: low
---

Delete all disposable scaffolding artifacts from `docs/` in the current working directory.

## Scope

Delete files in these dirs (relative to cwd):

| Dir | What to delete |
|-----|----------------|
| `docs/seeds/` | all files |
| `docs/prd/` | all files |
| `docs/tasks/` | all files |
| `docs/handoffs/` | `.md` files only — skip any non-`.md` files |

Never touch `docs/adr/` or `docs/prototypes/`. Never run git. Never edit `.gitignore`. After deleting files, remove any dirs that are now empty, including `docs/` itself if empty.

## Process

### 1. Parse args

If args include `--force` or `-y`, set `skip_confirm = true`. Otherwise `skip_confirm = false`.

### 2. Enumerate files

Run these Bash commands to build the file list:

```bash
find docs/seeds -maxdepth 1 -type f 2>/dev/null
find docs/prd -maxdepth 1 -type f 2>/dev/null
find docs/tasks -maxdepth 1 -type f 2>/dev/null
find docs/handoffs -maxdepth 1 -name "*.md" -type f 2>/dev/null
```

Collect all paths into a list. If the list is empty, report `Nothing to clean.` and stop.

### 3. Show preview

Print every file that will be deleted, grouped by directory:

```
About to delete:

  docs/seeds/
    seed-foo.json
    seed-bar.json

  docs/prd/
    prd-foo.html

  docs/tasks/
    tasks-foo.json

  docs/handoffs/
    handoff-foo.md

Total: N files
```

List every path. No dir-level summaries instead of filenames. If a dir has no files, omit it.

### 4. Confirm

If `skip_confirm` is false, use `AskUserQuestion` with:

- Question: `Delete N files? This cannot be undone in repos where these files are untracked.`
- Options: `Yes, delete all` / `No, cancel`

Stop if the user cancels.

### 5. Delete

Run `rm` with explicit enumerated paths. No `-f` flag. No bare `rm *`. No `find -delete`.

If the file count is large, batch into multiple `rm` calls, each listing explicit paths. Every path must be spelled out individually.

```bash
rm docs/seeds/file1.json docs/seeds/file2.json ...
rm docs/prd/file1.html docs/prd/file2.md ...
```

### 6. Remove empty dirs

After deletion, remove empty dirs with:

```bash
rmdir docs/seeds docs/prd docs/tasks docs/handoffs docs 2>/dev/null
```

`rmdir` only removes dirs that are truly empty, so `docs/adr/`, `docs/prototypes/`, and any other non-empty dirs survive automatically.

### 7. Report

Print a short summary: files deleted per dir, dirs removed, and total.
