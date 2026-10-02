# artifact-grounding-judge: hillclimb to improve fake detection

**Source ref:** `none` (no seed or task file; work originated in this conversation)

## What was done

Built a complete eval suite for the `artifact-grounding-judge` agent and ran a baseline measurement. The agent's job is to verify that quotes in learning records really appear in the files they cite, then save the record or reject it. The eval measures whether it does this correctly.

### Eval location

```
.claude/hillclimb/artifact-grounding-judge/
  _state.json                   # metrics, labels, case_notes path
  baseline/
    results.jsonl               # 138 rows (46 cases × 3 reps)
    traces/                     # gitignored — full transcripts per run
```

### Eval scripts

```
claude-code-shared/evals/artifact-grounding-judge/
  run-eval.mjs        # the runner (calls cch -p --agent artifact-grounding-judge)
  build_cases.py      # builds cases.jsonl + fixtures/ from learnings file
  cases.jsonl         # 46 labeled test cases
  case_notes.jsonl    # plain-English note per case (what was changed and why)
  cases.md            # human-readable version of cases.jsonl
  fixtures.lock.json  # frozen file versions (git sha per file)
  fixtures/           # gitignored — frozen source files from Quaestor-Web
  summarize.py        # quick CLI summary of a variant dir

claude-code-shared/scripts/
  eval-report.sh      # always use this instead of the builder directly
  eval-summary.py     # generates summary.html (plain-English) alongside report.html
```

### Baseline scores

| What | Score |
|---|---|
| Verdict correct (headline) | 94% (130/138) |
| Fakes caught | 90% (46/51) |
| Real records passed | 97% (84/87) |
| Confidence correct | 99% (137/138) |
| Write correct | 92% (127/138) |
| JSON-only format | 1% (1/138) |

Noise floor: approximately ±5 points overall, ±11 points on fake-catching. A prompt change must exceed that to count as a real improvement.

### Known weaknesses to fix

1. **Misses one-word fakes (79% catch rate).** Changed e.g. `updated_at` to `updatedAt` or `newest` to `oldest`. The judge reads the file and compares by eye instead of searching for the exact string. Fix: instruct it to use `grep -F` or `grep -c` to check for the exact quote text.

2. **Wrote a fake record before rejecting it.** In one run, the judge called `log-learning.py` first, then found a bad quote and returned `rejected`. The fake was already saved. Fix: check all quotes first. Only call `log-learning.py` after all pass.

3. **Two runs said pass but never saved.** The record was silently lost. Fix: a `pass` verdict must always include running `log-learning.py` and echoing its output in `write_output`.

4. **Ignores its output format.** Wraps JSON in a code block and adds prose before it. Lower priority — the upstream tracer copes. Fix: strengthen the format rule; move it to the end of the prompt.

### Target after fixes

- Fakes caught: ≥ 98%
- Real records passed: ≥ 97% (must not regress)
- Write correct: 100% (no saved fakes, no lost records)

## What to do next

### Step 1: re-approve the runner

The grader in `run-eval.mjs` was fixed (better JSON parser for fenced responses). The harness sha is now stale. Run once to record the new sha before hillclimbing:

```bash
cd ~/.dotfiles && EVAL_ONLY=none node claude-code-shared/evals/artifact-grounding-judge/run-eval.mjs \
  --flow .claude/hillclimb/artifact-grounding-judge --variant baseline --approve-harness
```

### Step 2: run /claude-api hillclimb

In a new `cch` session at `~/.dotfiles`:

```
/claude-api hillclimb
```

Tell it:
- **Flow dir:** `.claude/hillclimb/artifact-grounding-judge`
- **What to change:** only `claude-code-shared/agents/artifact-grounding-judge.md`
- **Budget:** ~$6/round, up to 3 rounds
- **Stop when:** fakes caught ≥ 98% AND write correct = 100% AND real records passed ≥ 97%

The hillclimb loop proposes a prompt edit, runs the eval as `v1`/`v2`/etc., and shows the summary page after each round.

### Step 3: build the report after each round

The rule in `CLAUDE.md` says to use `eval-report.sh`, but the hillclimb skill may not follow it automatically. After each round, if the summary page is missing:

```bash
cd ~/.dotfiles && claude-code-shared/scripts/eval-report.sh .claude/hillclimb/artifact-grounding-judge
```

Open `summary.html` first (plain English), then `report.html` for per-case detail.

## What NOT to commit

These are gitignored and also excluded in `repo-policy.json`:

- `.claude/hillclimb/*/traces/`
- `.claude/hillclimb/*/ref/`
- `.claude/hillclimb/*/trajectory/`
- `.claude/hillclimb/**/report.html`
- `.claude/hillclimb/**/summary.html`
- `**/evals/*/fixtures/`

Safe to commit: `cases.jsonl`, `case_notes.jsonl`, `run-eval.mjs`, `build_cases.py`, `fixtures.lock.json`, `_state.json`, `baseline/results.jsonl`, both scripts, `.gitignore`, `repo-policy.json`, `CLAUDE.md`.

Note: `claude-code-shared/evals/persona-accuracy/` was created by another session. Check it before committing everything.

## Key files

| File | Purpose |
|---|---|
| `claude-code-shared/agents/artifact-grounding-judge.md` | The agent to improve |
| `.claude/hillclimb/artifact-grounding-judge/_state.json` | Eval config + summary labels |
| `claude-code-shared/evals/artifact-grounding-judge/run-eval.mjs` | Runner (needs `--approve-harness` first) |
| `claude-code-shared/evals/artifact-grounding-judge/cases.md` | Human-readable test cases |
| `claude-code-shared/scripts/eval-report.sh` | Build both report.html and summary.html |

## Suggested skills

- `/claude-api hillclimb` — main next step, iterates the prompt against the eval
- `/claude-api build-eval` — if you need to add more test cases later
