# persona-accuracy hillclimb report (2026-10-02)

**Headline (held-out test, 16 cases x 3 reps, paired 95% CI):** quote_ok 0.24 -> 0.59 (+0.40 ±0.26), format_ok 0.00 -> 0.38 (+0.38 ±0.14); correct 0.83 -> 0.81 (-0.02 ±0.15, within noise). Cost $0.20 -> $0.27 per run.

## Changes now applied to `claude-code-shared/agents/personas/persona-accuracy.md` (v2)

- [TUNE] `transcript_span` must be an exact contiguous substring of one transcript message, with no wrappers, elisions or brackets, and with JSON escapes decoded. This is why quote_ok rose: baseline spans were wrapped as `User at line 43: "..."`.
- [TUNE] `field` must be a zero-based JSON path, never a line number.
- [TUNE] Findings now go in the message that carries the last tool call, and the final message is the bare array. This is why format_ok moved off 0: the model had been writing its conclusions as prose in the final message.
- [TUNE] The fenced, pretty-printed output example was replaced with a key list and a single-line unfenced example. Every non-empty baseline array had copied the fenced shape.

## Before / after (test cases, final replies)

- `ci-fix--negation-2` rep0. Baseline: `Based on my thorough review of the transcript, I found one critical semantic drift issue... [json fence] [ {...`. v2: `[{"persona": "accuracy", "field": "decisions[5]", "claim": "CircleCI MCP auth is not required..."`
- `ci-fix--drift-1` rep0. Baseline: `Based on my thorough investigation of the seed and transcript, I have found one clear semantic drift issue: [json fence] ...`. v2: `[{"persona": "accuracy", "field": "decisions[3]", ...`

Full transcripts are in `report.html` (Transcripts tab).

## Failure taxonomy

Harness and infra zeros were excluded throughout. They came from usage limits on ~/.cch, a mid-run CLI reinstall, and the original hook leak. None of them are in the scored rows. There were no refusals.

## What I'd try next

- **format_ok is capped at about 0.38.** About 60% of replies still open with a lead-in sentence. The remaining lever is outside the body. to-seed already parses leniently. The persona could be spawned with structured output instead. Prompt wording has hit diminishing returns.
- **Isolate v3's field_ok gain (+0.18 ±0.14)** without its step-5 rewrite.
- **Extra cost from v2's verify step.** Turns went from 18 to 27 median. Check whether the step-5 Grep can go without losing format_ok, since the analyzer found it did not help quote_ok.
- **Detection (correct) can't be climbed with this eval.** Test is at 0.83 against ±14pt noise. Moving it needs more cases (new bases) or more reps.
