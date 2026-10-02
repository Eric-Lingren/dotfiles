# v1: mechanical anchor check + verify-all-then-write

Source: user-named fix (handoff 20261001-2309, items 1-3). No analyzer this round.
Caveat: the handoff's failure diagnosis came from a session that read all baseline traces, before the train/test split existed. Test is not fully clean for this round's hypothesis.

## Behavior targeted
1. Missed one-word fakes (fabricated 79%, 5 misses). Judge compared quotes by eye.
2. Wrote a record then rejected it (write before all anchors checked).
3. Said pass but never called log-learning.py (lost record).

## Change (one hypothesis: the judge decides by reading instead of checking)
- Replace "read file, search for quote" with a whitespace-normalized exact-substring check (python3 one-liner). Prints MATCH / NO_MATCH + quote words absent from file / MISSING.
- NO_MATCH: classify by token comparison. Identifier/number/meaning word differs -> reject. Only connecting words differ -> pass, candidate.
- Absence anchors: grep -niF key terms instead of reading.
- Settle the verdict over all entries before any write. Explicit combine rule.
- A pass must call log-learning.py and echo write_exit/write_output.

## Expected
fabricated misses -> ~0. write_correct -> ~100%. Risk: paraphrase cases over-rejected (watch real-pass guardrail).
