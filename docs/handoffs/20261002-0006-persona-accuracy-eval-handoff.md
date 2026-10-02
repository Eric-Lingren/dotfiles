# persona-accuracy Eval: Baseline Done, Ready to Hillclimb

**Source ref:** `none` (no seed file; ad-hoc eval build session)

## What was built

A full eval for `claude-code-shared/agents/personas/persona-accuracy.md`.

**Flow dir:** `.claude/hillclimb/persona-accuracy/`

The persona takes a draft seed (`seed_path`) and a cleaned transcript (`transcript_path`), then returns a JSON array of refutations where seed decisions diverge from what the transcript actually decided.

### Case set

- **33 cases** across 3 real to-seed sessions (ci-fix, improve-learnings, relay-posting).
- Each session was cut at the exact point to-seed spawned `persona-accuracy`. Transcript filtered through `filter-session-transcript.sh`. Draft seed recovered from the session log.
- **Mutations** in `claude-code-shared/evals/persona-accuracy/mutations.json`: 2 per defect type per base → 24 planted, 6 distractor, 3 clean.
- Defect types: `drift`, `stale`, `scope`, `negation` (planted); `fabricated-rationale` (distractor, Grounding lens).

### Baseline result (claude-haiku-4-5, 3 reps, 99 runs)

| metric | score | note |
|---|---|---|
| correct | 78% ±8% | main headline |
| recall | 81% ±9% | catches planted defects |
| specificity | 70% ±17% | stays quiet on clean/distractor |
| field_ok | 83% ±10% | right `decisions[N]` when it catches |
| quote_ok | 19% ±9% | spans are paraphrased, not verbatim |
| **format_ok** | **0%** | all 99 replies start with prose or a code fence; contract says bare JSON array |
| covered | 99% | hit the coverage-limit error path once |

Total cost: **$26.15**. Median latency: **103s**. Median cost/run: **$0.26**.

## Key grading decisions (made in the eval-build session)

These are not in the code comments; they live only in this handoff.

1. **Claim-or-field matching.** A refutation counts as hitting the planted case if its `field` matches OR its `claim` quotes the changed text. Personas sometimes cite a line number as the index. The separate `field_ok` metric scores the index accuracy.

2. **relay-posting--clean is labeled `[]` (no refutation expected).** The persona flagged `decisions[0]` for dropping "for now" from "github only for now". Decided: faithful enough. `decisions[0]` says "Linear and Slack adapters remain copy-only stubs" which preserves the temporariness.
   - **OPEN QUESTION:** `relay-posting--clean` also has a real defect: `decisions[11]` says "Three schemas updated" but the transcript lists two. The persona caught this in 1/3 reps. The case is currently labeled clean (those catches score as false positives). **Recommend relabeling to expect a refutation on `decisions[11]`.** This is a free regrade from saved traces, but it changes `cases.jsonl` and requires a harness re-approval.

3. **Distractors (off-lens) count as failures if flagged.** `fabricated-rationale` defects are the Grounding persona's lens, not Accuracy. If Accuracy flags them, that's a specificity miss.

4. **`quote_ok` is strict verbatim.** Any wrapper (`"User at line 43: ..."`, `[user: a]`, elided spans) fails. Judges use the span as evidence, so a fabricated-looking quote is a real defect.

## Files

### Committed / to commit

All under `claude-code-shared/evals/persona-accuracy/` (264 KB total):
- `run-eval.mjs` — runner (copy of artifact-grounding-judge scaffold with persona-accuracy fill-in)
- `build_cases.py` — extracts fixtures from session logs, applies mutations
- `mutations.json` — 30 hand-authored defect mutations with transcript anchors
- `cases.jsonl` — 33 case rows (regenerated from `build_cases.py`)
- `cases.md` — human review sheet (generated)
- `fixtures.lock.json` — sha256 of `transcript.jsonl` and `seed.clean.json` per base
- `.gitignore` — excludes `fixtures/` (private session content)

Under `.claude/hillclimb/persona-accuracy/`:
- `_state.json` — metrics, perf fields, harness sha, plain-English summary block
- `baseline/results.jsonl` — 99 graded rows (can omit if you want no transcript quotes in git)

### Gitignored (not committed)

- `baseline/traces/` — full conversation traces
- `fixtures/` — extracted session transcripts and seeds (private)
- `report.html`, `summary.html` — generated

### Regenerating fixtures

```bash
cd ~/.dotfiles && python3 claude-code-shared/evals/persona-accuracy/build_cases.py --extract
```

Requires the origin session JSONLs still on disk at `~/.cch/projects/` and `~/.cco/projects/`. When those get pruned, the local `fixtures/` is the only copy.

## Known issues / hillclimb targets

### High priority

- **`format_ok` is 0/99.** The persona's instruction says "JSON only, no fences, no prose." In practice every reply wraps `[]` in analysis prose plus a code fence. to-seed parses leniently, but the contract is clear. Fix: add a concrete negative example to `persona-accuracy.md`. This is the highest-leverage change.

- **`quote_ok` is 19%.** Spans look like `"User at line 43: \"...\""` or splice `[user: a]` into the transcript. Fix: tell the persona the span must be a substring of the file it read, with no wrapper, ellipsis, or annotation.

### Medium priority

- **Worst-scoring cases** (0/3 or 1/3): `relay-posting--drift-1` (planted "after the first release" vs transcript "once proven reliable"), `relay-posting--scope-2`, `improve-learnings--scope-1`, `ci-fix--stale-2`. Three of the four are on relay-posting, so transcript size (ci-fix is 706K) is not the explanation. Read their traces before guessing a cause.

- **Specificity on clean seeds: 5/9.** Two false positives on relay and improve-learnings. Partially a labeling issue (see item 2 above). Partially real over-flagging.

### Low priority

- **Field index errors.** `field_ok` is 83%, not 100%. The persona sometimes writes the decision's line number rather than the `decisions[N]` path. Minor: the claim text still identifies the right content.

## How to run hillclimb

```bash
# in a new session, from ~/.dotfiles:
/claude-api hillclimb
```

Point it at `.claude/hillclimb/persona-accuracy`. The target to improve is `claude-code-shared/agents/personas/persona-accuracy.md`.

After any harness file edit (runner, cases, mutations), re-approve:

```bash
node claude-code-shared/evals/persona-accuracy/run-eval.mjs \
  --flow .claude/hillclimb/persona-accuracy \
  --variant baseline --model claude-haiku-4-5 \
  --approve-harness
```

Each full pass (99 runs): ~$26, ~30 min at concurrency 6.

A change needs to move the headline more than ~10 points to be above the noise floor (±8% CI at 99 runs). Fixing `format_ok` won't move `correct` at all: the grader parses leniently, so format is scored separately. Fixing `recall` on the hard cases (drift/scope on large transcripts) is the real win.

## Suggested skills

- `/claude-api hillclimb` — iteratively improve `persona-accuracy.md` against this eval
- `/claude-api build-eval` — if you want to add more cases (different seeds/sessions)
- `/improve-skill-benchmarks` — alternative eval loop for the persona
