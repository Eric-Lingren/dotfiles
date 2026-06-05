---
name: clean-scaffolding
description: Delete all disposable doc scaffolding (seeds, PRDs, tasks, handoffs) in the current working tree. Leaves docs/adr/ and docs/prototypes/ untouched. Use when done with a workflow and ready to clear the clutter. Pass --force or -y to skip the confirmation prompt.
argument-hint: "--force or -y to skip confirmation"
model: haiku
effort: low
---

Delete disposable scaffolding artifacts from `docs/` in the current working directory.

This skill is **lineage-aware**: it groups artifacts by their provenance chain and only deletes a chain atomically when the entire chain is consumed. It refuses partial deletions that would leave dangling source refs.

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

Read every JSON file in `docs/seeds/`, `docs/prd/`, and `docs/tasks/` (do not delete anything yet). Build a lineage chain for each root artifact:

**Walk the chain:**
1. A root artifact has `source: null` or `source.type = "session"` (no upstream document).
2. A child artifact has `source.ref` pointing to a file in the chain (e.g. a PRD whose source.ref is a seed, or a task file whose source.ref is a seed or PRD).
3. Group artifacts into chains: `{root, children[]}`. An artifact that isn't referenced by anyone is a standalone chain of one.

**Check completeness (consumed):**
For each chain, a chain is "fully consumed" when:
- If the chain includes task files: every task in every task file within the chain has `status: "done"` or `status: "merged"`. Any task with `status: "not_started"`, `"in_progress"`, or `"blocked"` means the chain is NOT consumed.
- If the chain has no task files (seed + optional PRD only, no tasks generated yet): the chain is consumed only if the user explicitly says it was discarded or never progressed. Otherwise treat as not consumed.

**A partial chain is NEVER deleted.** If artifact B references artifact A via `source.ref`, and A would be deleted but B would not (because B is outside the deletion scope), refuse to delete A and explain the dangling ref.

### 4. Report chains

After analysis, categorize each chain:

- **Ready to delete**: fully consumed.
- **Not consumed**: tasks still in progress or not started.
- **Partial (dangling ref)**: a child artifact is referenced by something outside the chain.

Report all categories to the user before asking to confirm.

### 5. Confirm

If `skip_confirm` is false, call `AskUserQuestion`:

- List only the chains in the "ready to delete" category and the count of files.
- Question: `Delete N files across M chains? This cannot be undone in repos where these files are untracked.`
- Options: `Yes, delete confirmed chains` / `No, cancel`

Stop if the user cancels or if no chains are ready to delete. If `skip_confirm` is true, skip this step.

### 6. Delete (atomic, per confirmed chain)

For each confirmed chain, collect all files in the chain (root seed + any PRDs that reference it + any task files that reference it or the PRDs). Delete them in one atomic sweep using the script's `delete-files` mode:

```bash
bash ~/.dotfiles/claude-code-shared/skills/clean-scaffolding/scripts/clean-scaffolding.sh \
  delete-files <file1> <file2> ...
```

This mode deletes only the specified files and removes any now-empty directories.

### 7. Report

Relay the script's `removed ...` lines and `Deleted N files.` summary. Note any chains that were refused (not consumed or dangling ref) and what the user must do before those chains can be cleaned.

<!-- learning-capture:start -->
## Learning Capture

**Default: write nothing.** Most runs record nothing. Only proceed if an observable
correction-event occurred this run — a tool failure you had to work around, a backtrack,
a user correction, an instruction gap, or redundant work you repeated.

### Step 1 — assess whether a correction-event occurred

If no correction-event: stop here. Do not call the judge. Do not call the writer.

### Step 2 — build a candidate entry

Construct this JSON object (do not include schema_version or timestamp; the writer injects them):

```json
{
  "skill": "<this skill's slug, e.g. debug>",
  "trigger": "<tool_failure | backtrack | user_correction | instruction_gap | redundant_effort | uncategorized>",
  "trigger_label": "<snake_case label if trigger == uncategorized, else null>",
  "evidence": "<WHAT happened this run. Observable, run-specific. For aggregated events (redundant_effort, backtrack, or any tried-N-times observation) list discrete quoted transcript anchors — not a bare count. The judge counts len(anchors).>",
  "learning": "<WHY it happened and the general reusable rule that must hold beyond this run. If this sentence only describes this run it belongs in evidence, not here.>",
  "suggested_fix": "<the concrete skill or script edit that would prevent recurrence, or null>"
}
```

Enumerate-discrete-anchors: for any aggregated observation, evidence must quote each
individual anchor explicitly. Example — correct: "Ran Glob three times: step 2 ('no
results'), step 5 ('no results'), step 8 ('found debug.jsonl')." Incorrect: "Ran Glob
three times without finding the file."

### Step 3 — grounding gate

Spawn the `learning-grounding-judge` agent (`subagent_type: learning-grounding-judge`,
model: haiku). Pass it:

```
## Entry
<candidate entry JSON>

## Transcript path
<absolute path to the session transcript file>
```

The agent returns `{"grounded": true|false, "reason": "..."}`.

### Step 4 — write or discard

If `grounded: true`:
```bash
echo '<entry JSON>' | python ~/.dotfiles/claude-code-shared/scripts/log-learning.py
```

If `grounded: false`: write nothing. The agent's reason explains what anchor was missing.
<!-- learning-capture:end -->
