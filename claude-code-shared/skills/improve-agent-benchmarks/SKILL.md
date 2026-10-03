---
name: improve-agent-benchmarks
description: Cheap iterative improvement of a shared agent. Runs the next stage for the chosen agent (contract, cases, iterate). Contract stage drafts a cited, history-validated contract.json with an Opus subagent, shows each check with its source, historical pass rate and real failing examples, and freezes it on approval. Use when the user invokes /improve-agent-benchmarks [agent-name].
---

# improve-agent-benchmarks

Usage: `/improve-agent-benchmarks [agent-name]`. No flags. The only argument is the optional agent name. The user never picks a stage: the skill runs the next stage recorded in the queue for that agent.

All mechanical work lives in `~/.dotfiles/claude-code-shared/scripts/agent-eval/`. Call the scripts, do not redo their work in prose. Grading is deterministic (`grade.py`); no LLM ever scores an agent output. Custom grading code never goes in an agent folder.

Data locations (scripts resolve them): queue `.claude/agent-bench/queue.json`, history and drafts `.claude/agent-bench/<agent>/`, frozen `claude-code-shared/evals/<agent>/contract.json` and `baseline.json`.

## Step 1: pick the agent

If an agent name was given, use it. Otherwise run:

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/bench_queue.py list
```

Show the agents as a simple list (name and stage) and ask which one with AskUserQuestion, accepting any typed name. Ranking comes in a later task; do not rank.

## Step 2: queue entry

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/bench_queue.py ensure <agent>
```

This creates the entry at stage `contract` if missing (and adds any agent missing from the queue). Read the printed `stage`. If it is `contract`, run the contract stage below. Other stages are not built yet: say so and stop.

## Contract stage

### 1. Harvest history (free)

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/harvest.py <agent>
```

### 2. Draft with Opus

Run the source bundler and capture its output:

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/contract_sources.py <agent>
```

Spawn one Agent with `model: "opus"` (general-purpose). Give it the bundler output and these rules, and have it write `.claude/agent-bench/<agent>/draft.contract.json` (resolve to the repo root):

- Three sources only: `role` (the agent's .md), `caller` (each consumer and what it parses), `side_effect` (files written, required tool calls).
- Every check carries `source: {"tag": "role|caller|side_effect", "file": "<path relative to claude-code-shared/>", "line": "N" or "N-M", "quote": "<verbatim text from those lines>"}`. A check with no citable source must not be written.
- Check types: exactly these 7 built-ins, with the params documented in the `grade.py` header: `json_parse`, `schema`, `quote_in_input`, `tool_called`, `file_written`, `verdict_equals`, `no_prose`. Use `when` for checks that only apply to some outputs (for example a side effect only on a pass verdict).
- If a rule cannot be expressed by a built-in, write the check with `"type": "proposed:<name>"` and a `"proposal"` string explaining the rule. Do not write grading code.
- Where two sources disagree (for example the role file says bare JSON, a caller parses loosely), do not choose. Add an entry to `conflicts`: `{"id", "description", "options": [{"label", "check": {<full check with its own source>}}, ...]}` with at least two options.
- Output shape: `{"agent": "<agent>", "checks": [...], "conflicts": [...]}`.

### 3. Validate and show the approval screen

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/contract_review.py <agent>
```

The script drops checks whose citation is not real (missing file, line out of range, quote not found), runs `grade.py`'s engine over the harvested history, and prints per check: source tag, file:line, historical pass rate, and 1 or 2 real failing examples. It also lists source disagreements, proposed new types and dropped checks. Relay the full screen to the user in chat (do not rely on collapsed tool output).

### 4. Resolve before approval

- Each source disagreement: ask the user to pick a winner, then run `contract_resolve.py <agent> <conflict-id> <option-number>`.
- Each proposed new type: needs explicit user approval. If approved, add the type to the shared `grade.py` (and its header), change the check's type to the new name, and re-run step 3. If refused, remove the check from the draft.
- Re-run `contract_review.py` after any change so the user sees the final screen.

### 5. Approve and freeze

Ask the user to approve the contract (AskUserQuestion: approve / change something). Only on approval:

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/contract_freeze.py <agent>
```

This writes `contract.json` with a sha256 fingerprint of every cited file, saves the historical pass rates as `baseline.json` (the free baseline, recomputed by the same engine as `grade.py`), and advances the queue entry to stage `cases`. It refuses while conflicts or proposed types remain. Report the frozen check count and baseline to the user. Commit only `contract.json` and `baseline.json`; history, drafts and fixtures are never committed.

<!-- cases-stage:start -->
## Cases stage

Runs when the queue stage printed in Step 2 is `cases` (this section supersedes the "other stages are not built yet" note in Step 2). Scripts are in `~/.dotfiles/claude-code-shared/scripts/agent-eval/`. Fixtures live in `claude-code-shared/evals/<agent>/fixtures/` (gitignored); they are never committed.

### 1. Import legacy cases (once, only if the agent has them)

If `claude-code-shared/evals/<agent>/cases.jsonl` exists in the old shape (artifact-grounding-judge, persona-accuracy), run once:

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/cases_import.py <agent>
```

It keeps every legacy case and its expected answer as an `imported` case and moves the old file to `cases.legacy.jsonl` (the folder's `build_cases.py` and `run-eval.mjs` read that name).

### 2. Freeze real inputs

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/harvest.py <agent>
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/cases_freeze.py <agent>
```

Picks 4 to 6 recent, varied spawns, freezes each prompt and the files it referenced, and writes `cases.lock.json` (sha256 per file) plus `real` cases with the agent's recorded answer as the expected answer. Files that are gone are rebuilt from the spawn's own reads or the parent session log; otherwise the spawn is skipped and the reason is printed. Relay the printed list (cases, skips, `judgment_agent`) to the user in chat.

### 3. Planted defects (only when the script printed `judgment_agent: yes`)

Spawn one Agent with `model: "sonnet"`. Give it the frozen real cases (`cases.jsonl`, each `fixtures/<id>/prompt.txt` and files) and the agent's contract. Have it write `.claude/agent-bench/<agent>/proposals.json`: a JSON list, one entry per planted case, 1 to 2 per real case, each a single find/replace edit that should change the correct answer:
`{"id", "base": "<real case id>", "target": "prompt" or a path under that case's frozen files, "find": "<exact text>", "replace": "<text>", "expected": {<expected answer for the edited input, same shape as the base case's expected>}, "note": "<why the answer changes>"}`. The subagent proposes only; it never edits fixtures.

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/cases_plant.py <agent>
```

The script rejects any edit whose `find` matches zero times or two-plus times (reason printed, never written) and prints a diff of each accepted edit against its clean base. Relay rejections and diffs to the user. If rejected proposals leave too few planted cases, send the reasons back to the Sonnet subagent for one corrected round.

### 4. Verify and advance

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/agent-eval/cases_finish.py advance <agent>
```

Re-hashes every fixture against `cases.lock.json`, checks every case has an expected answer and every planted edit still applies, then advances the queue entry to `iterate`. Commit `cases.jsonl`, `cases.lock.json` and any `cases.legacy.jsonl`; never fixtures, proposals or queue state.
<!-- cases-stage:end -->

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `improve-agent-benchmarks`.
<!-- skill-done: improve-agent-benchmarks -->
<!-- learning-capture:end -->
