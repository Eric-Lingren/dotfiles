# v2: move narration out of the final message; drop the fenced template (analyzer, train-only)

Target: format_ok (0/20 train reps under v1). Evidence from 20 train v1 traces (hooked-free, ~/.cch run, archived):
- 20/20 final messages open with prose ("Based on my..." 17/20), prose and JSON in the same final text block, right after the last tool_result.
- 17/17 non-empty arrays are wrapped in ```json and pretty-printed like the body's own fenced example; 0/3 `[]` replies are fenced.
- 10/20 final messages still narrate a next step ("Let me verify...") before answering; relay-posting--clean_rep1 concludes a drift in prose then returns `[]` (also a recall loss).

Root cause: the model writes its conclusions as report prose in the last message (its narrate-then-act habit), and copies the fenced multi-line example as the answer template. v1's wrong/right list did not override the template.

Change (one behavior, three hunks): (1) shorter output rule saying where analysis goes; wrong/right list removed (it itself showed a fence); (2) Process steps 5-6: findings are written alongside a final span-verifying Grep, then the final message is the array only; (3) fenced example replaced by a key list and a single-line unfenced example.

Risks: a step-5 Grep miss on punctuation-heavy spans could make Haiku drop a true refutation (recall); explicit findings could raise false positives on clean seeds (specificity). Extra Grep adds ~1 turn.
Note: analyzer said "no thinking channel"; traces do bill thinking tokens (display omitted), so the claim is overstated; the fix does not depend on it.
