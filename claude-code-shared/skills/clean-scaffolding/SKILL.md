---
name: clean-scaffolding
description: Archive consumed doc scaffolding (seeds, PRDs, tasks, handoffs) in the current working tree. Bundles each fully-consumed lineage chain verbatim into docs/archive/. Leaves docs/adr/ and docs/prototype/ untouched. Deletes browser-checks and task trace logs without archiving. Use when done with a workflow and ready to clear the clutter. Pass --force or -y to skip the confirmation prompt.
argument-hint: "--force or -y to skip confirmation"
model: haiku
effort: low
---

Archive consumed scaffolding artifacts from `docs/` in the current working directory.

This skill is **lineage-aware**: it groups artifacts by their provenance chain and only archives a chain atomically when the entire chain is consumed. It refuses partial operations that would leave dangling source refs.

**Three-way disposition:**
- **Archive set** (bundle then remove originals): `docs/seeds/`, `docs/prd/`, `docs/tasks/`, `docs/handoffs/`
- **Delete set** (remove without archiving): `docs/browser-checks/`, `docs/tasks/.logs/`
- **Untouched**: `docs/adr/`, `docs/prototype/`

## Process

### 1. Parse args

If args include `--force` or `-y`, set `skip_confirm = true`. Otherwise `skip_confirm = false`.

### 2. Preview (ALWAYS run this first)

Run:

```bash
bash ~/.dotfiles/claude-code-shared/skills/clean-scaffolding/scripts/clean-scaffolding.sh preview
```

This prints the full grouped file list and a total to the terminal.

- Exit code 2 (output `Nothing to clean.`): report `Nothing to clean.` and stop.
- Exit code 0: proceed to lineage analysis.

### 3. Lineage analysis

Read every JSON file in `docs/seeds/`, `docs/prd/`, and `docs/tasks/`. Read every `.md` file in `docs/handoffs/` (extracting `Source ref:` from the header for provenance). Build a lineage chain for each root artifact:

**Walk the chain:**
1. A root artifact has `source: null` or `source.type = "session"` (no upstream document).
2. A child artifact has `source.ref` pointing to a file in the chain (e.g. a task file whose `source.ref` is a seed basename, or a PRD whose `prd-provenance` source.ref is a seed).
3. For handoff `.md` files: extract the upstream seed basename from the `**Source ref:** \`<basename>\`` header line.
4. Group artifacts into chains: `{root, children[]}`. An artifact not referenced by anyone is a standalone chain of one.

**Check completeness (consumed):**
For each chain, a chain is "fully consumed" when:
- If the chain includes task files: every task in every task file within the chain has `status: "done"` or `status: "merged"`. Any task with `status: "not_started"`, `"in_progress"`, or `"blocked"` means the chain is NOT consumed.
- If the chain has no task files (seed + optional PRD only, no tasks generated yet): the chain is consumed only if the user explicitly says it was discarded or never progressed. Otherwise treat as not consumed.

**A partial chain is NEVER archived.** If artifact B references artifact A via `source.ref`, and A would be archived but B would not (because B is outside the archive scope), refuse and explain the dangling ref.

### 4. Report chains

After analysis, categorize each chain:

- **Ready to archive**: fully consumed.
- **Not consumed**: tasks still in progress or not started.
- **Partial (dangling ref)**: a child artifact references something outside the chain.

Report all categories to the user before asking to confirm.

### 5. Confirm

If `skip_confirm` is false, call `AskUserQuestion`:

- List only the chains in the "ready to archive" category and the count of files.
- Question: `Archive N files across M chains?`
- Options: `Yes, archive confirmed chains` / `No, cancel`

Stop if the user cancels or if no chains are ready to archive. If `skip_confirm` is true, skip this step.

### 6. Archive (atomic, per confirmed chain)

For each confirmed chain:

**Archive-set files** (seeds, tasks, handoffs, prd): collect all files in the chain and bundle them using the `archive-files` mode. The script writes a verbatim bundle to `docs/archive/<root-timestamp>-<slug>.json`, then removes the originals.

```bash
bash ~/.dotfiles/claude-code-shared/skills/clean-scaffolding/scripts/clean-scaffolding.sh \
  archive-files <file1> <file2> ...
```

**Delete-set files** (browser-checks, task trace logs): delete without archiving using `delete-files` mode:

```bash
bash ~/.dotfiles/claude-code-shared/skills/clean-scaffolding/scripts/clean-scaffolding.sh \
  delete-files <file1> <file2> ...
```

Both operations are atomic per chain sweep.

### 7. Report

Relay the script's `archived … to …`, `removed …`, and summary lines. Note any chains that were refused (not consumed or dangling ref) and what the user must do before those chains can be archived.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `clean-scaffolding`.
<!-- skill-done: clean-scaffolding -->
<!-- learning-capture:end -->
