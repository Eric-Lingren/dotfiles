# persona-accuracy hillclimb (final)

Account ~/.cco, claude-haiku-4-5, CLI 2.1.287, user hooks/plugins disabled, 33 cases x 3 reps, split 17 train / 16 test. Target: quote_ok + format_ok. Guardrails: correct, recall, specificity, field_ok, covered. Deltas are paired over test cases, 95% CI.

| round | change | test quote_ok | test format_ok | test correct | train quote_ok | train format_ok | train correct | $/run | spend |
|---|---|---|---|---|---|---|---|---|---|
| 0 | baseline | 0.24 | 0.00 | 0.83 | 0.36 | 0.00 | 0.80 | $0.20 | $20.43 |
| 1 | verbatim-span + field-path rules, bare-JSON wording | **0.66** (+0.35 ±0.30) | 0.00 | 0.81 | 0.76 | 0.00 | 0.80 | $0.21 (1.1x) | $42.72 |
| 2 (winner) | findings moved to last tool turn; fenced template removed | 0.59 (+0.40 ±0.26 vs base) | **0.38** (+0.38 ±0.14) | 0.81 (-0.02 ±0.15) | 0.74 | 0.31 | 0.78 | $0.27 (1.4x) | $71.00 |
| 3 (reverted) | draft array once with span Greps | 0.65 | 0.29 (-0.08 ±0.17 vs v2) | 0.81 | 0.65 | 0.29 | 0.73 | $0.24 (1.2x) | $95.88 |

**Recommended change.** Ship v2 of `claude-code-shared/agents/personas/persona-accuracy.md`. It combines the v1 and v2 edits.

**Versus baseline (test).** quote_ok went from 0.24 to 0.59 (+0.40 ±0.26). format_ok went from 0.00 to 0.38 (+0.38 ±0.14). Detection held: correct moved 0.83 to 0.81 (-0.02 ±0.15), and recall and specificity stayed within noise. Cost rose from $0.20 to $0.27 per run, and median turns from 18 to 27.

**Why trust this.** The test split was never read by the analyzers. Both gains clear paired noise on held-out cases, and each is tied to a mechanism visible in train traces. Replies now quote spans verbatim instead of wrapping them as `User at line N:`. In about a third of runs, the final message is now the bare array instead of "Based on my review..." plus a json fence.

**What else was tried.** v3 rewrote step 5 as "draft the array once, alongside span-check Greps, no further checks". It did not raise format_ok (0.29 vs 0.38) and halved train specificity, so it was reverted. v3 did raise field_ok by +0.18 ±0.14, which may be worth isolating later.

**Harness changes made during the loop (each approved by the user via --approve-harness).**
- The `relay-posting--clean` case was relabeled to expect a refutation on its real `decisions[11]` count defect.
- New `--regrade` mode re-scores stored traces.
- User hooks and plugins are disabled in spawned runs (`--settings disableAllHooks`). The first baseline ran with caveman/style hooks that production subagent spawns never get.
- `DISABLE_AUTOUPDATER` is set in spawned runs.
- No-model results and mid-session usage-limit notices are now recorded as harness errors instead of scored zeros.
- The default config dir is now `~/.cco`.

Earlier runs are archived in `_archive-*/`.
