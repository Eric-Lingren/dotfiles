| round | change | test verdict | train verdict | test fakes | test real | test write | $/run | s/case | tools | spend |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | baseline | 0.942 | 0.942 | 0.917 | 0.956 | 0.899 | $6.33 | 31.2 | 3.1 | 6.33 |
| 1 | mechanical anchor check + verify-then-write | 0.913 | 0.928 | 0.958 | 0.889 (down) | 0.913 | $7.63 (1.2x) | 45.5 (1.5x) | 6.1 (2.0x) | 13.95 |
| 2 | classify NO_MATCH by quote type | 0.928 | 0.957 | 0.958 | 0.911 | 0.913 | $8.09 (1.3x) | 47.7 (1.5x) | 6.6 (2.1x) | 22.04 |
| 3 | check-anchors.py reads quotes from the record | **0.986** | **1.000** | **1.000** | 0.978 | **0.986** | $4.22 (0.67x, down) | 27.4 (0.9x) | 2.0 (0.6x, down) | 26.26 (+~$0.5 canaries) |

**Recommended change.** Keep v3: `claude-code-shared/scripts/check-anchors.py` (new) plus the rewritten verification section of `claude-code-shared/agents/artifact-grounding-judge.md`. The judge pastes the record once into a script that checks every quote mechanically (whitespace-normalized exact match, closest passage on a miss). It classifies misses by quote type: code must match exactly, prose is judged by its claims. It writes only after every anchor is settled.

**Versus baseline (test, held out, 23 cases x 3 reps).** Verdict 0.942 -> 0.986 (paired delta +4.3 pts, 95% CI +/-7.5: positive but not significant alone; baseline was near ceiling). Write correct 0.899 -> 0.986 (+8.7, CI +/-8.4: just clears). Fakes caught 22/24 -> 24/24. Real records 0.956 -> 0.978. Cost per pass -33%, tool calls -36%, latency -12%. Train moved the same way (0.942 -> 1.000), so no generalization gap.

**Why trust this.** The grader is deterministic (verdict string plus actual lines in the sandboxed learnings sink), not an LLM judge. The script ran in 138/138 v3 traces. Explanations name the right reasons (camelCase rename, altered array literal, paraphrase supported by passage). 0 harness errors. Remaining miss: absence_true_b015 rep2 (one true absence claim rejected).

**What else was tried.** v1 replaced eyeballing with an inline exact check. It fixed fakes but its "any meaning-bearing word differs = fake" rule rejected half the real paraphrases. v2 judged prose by claims, restoring paraphrases, but the judge still hand-copied quotes into the check and sometimes pasted file text instead (fake reads as MATCH). v3 removed the copying. Process caveat: v1's hypothesis came from a pre-split handoff that had seen all baseline traces; v2 and v3 came from train-only analysis.

**Not done / next.** JSON-only output (format_ok 0%) was out of scope; the caller copes. Write-correct is 98.6%, not 100%. One absence false-reject. Absence anchors still use free-form grep; check-anchors.py could take an explicit absence-term list. Infra note: runs stall when the Mac sleeps (CLI StreamSuspended); run under `caffeinate -dims` with `--timeout-s 600`.
