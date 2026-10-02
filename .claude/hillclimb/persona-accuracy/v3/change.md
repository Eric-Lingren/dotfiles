# v3: write the answer once as a draft array at a recognizable point (analyzer, train-only)

Target: format_ok (train 16/51 under v2). Evidence from 51 v2 train traces:
- All 35 failures are prose before the array (23 "Based on my...", 11 "Perfect!/Excellent/Now..."); 17 short lead-ins, 18 full reports.
- Step 5 skipped in 15/35 failures vs 0/16 passes: its trigger "last tool call" is unrecognizable, so the model loops on "final" checks (median 3 "final" mentions, ~7 tool calls after the first), which also explains turns 20->27.
- 20/35 did step 5 and still wrote prose: step 5 asked for prose findings, and the final reply restated them.
- Step 5's Grep did not help quote_ok (train 0.76 -> 0.74).

Change: step 5 becomes "once every decision and summary sentence is compared, send one message whose text is the draft array, with one Grep per cited span in the same message; no further checks". Step 6: final message is the draft array again, re-copying any span whose Grep missed. Output rule updated to match.

Risks: "no further checks" could stop early (recall); a missed-span fix without re-check could dip quote_ok slightly. Expected: fewer turns.
