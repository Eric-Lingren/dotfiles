# v2: classify NO_MATCH by quote type (code exact, prose by claims)

Source: fresh analyzer, train traces only. Stacks on v1.

## Behavior
v1's rule called any differing "meaning-bearing word" fabricated, and allowed only connecting-word changes for a paraphrase. So every real paraphrase read as a fake. 4 of 9 paraphrase train reps (paraphrase_b000 r1,r2; paraphrase_b030 r0,r2) found the right passage and rejected anyway, e.g. b000_rep2: "Differences in meaning-bearing words: ... Quoted: Merge | File: Unify". Contrast b030_rep1 (same input): "meaning is identical" -> pass.

## Change
- Ordered tests on NO_MATCH: no passage -> fake. Code quote must equal passage exactly; identifiers/paths/numbers in prose must match char for char -> else fake. Prose: compare one-line claims; fake only if direction/order/quantity/yes-no reversed, actor/condition changed, or new claim. The "not in file" list alone is never a reason to reject.
- Script: case-insensitive word list; prints CLOSEST passage.

## Expected
Paraphrase 5/9 -> 8-9/9 train. Code fakes hold (test 2 stricter). Risk: wrong_file accepted as paraphrase of a loosely related passage.

## Not addressed (separate behaviors)
- paraphrase_b015_r0: pass without calling log-learning.py (1/9).
- fabricated_b131_r0: agent pasted file text into heredoc instead of the record's quote -> MATCH.
