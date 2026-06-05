---
name: cc-usage-analytics
description: View and explore Claude Code usage analytics — model mix, estimated cost, request intent, weekly trend, and per-skill tier adherence across the office (cco) and home (cch) profiles. Use when the user wants to see usage stats, run the benchmark, view the weekly report, check if model spend/tiers are trending right, or invokes /cc-usage-analytics.
model: sonnet
effort: medium
---

Surface and explore Claude Code usage analytics. All tools live in
`~/.dotfiles/claude-code-shared/`. Run commands, then present a tight summary,
not the raw dump.

## Commands

Benchmark (`scripts/cc-usage-benchmark.py`):
- Full report, both profiles: `python3 ~/.dotfiles/claude-code-shared/scripts/cc-usage-benchmark.py`
- One profile: add `--profile office` or `--profile personal`
- Weekly model trend (mix + est cost): append `--trend`
- Tier adherence (expected vs actual model per skill): append `--adherence`

Weekly report (`scripts/weekly-usage-report.sh`):
- Regenerate now: `bash ~/.dotfiles/claude-code-shared/scripts/weekly-usage-report.sh`
- Latest saved report: read the newest file in `~/.cache/cc-usage-reports/usage-*.txt`
- Auto-runs Mondays 9am via launchd (`com.ericlingren.cc-usage-report`)

## How to respond

1. Read intent: quick snapshot, trend over time, tier adherence, a single
   profile, or a deep dive. For an open "show my usage", run the full benchmark
   plus `--trend`.
2. Run the matching command(s).
3. Summarize, do not paste the raw output. Lead with headline numbers (model
   mix, est cost, top request intents), then trend direction, then adherence gaps.
4. Surface 1-3 actionable observations. Examples: "Opus share climbing week over
   week", "tldr-tech ran on opus but is tiered sonnet (drift)", "T3 default holding".
5. Offer next actions: re-tier a skill, change the session model, or drill into a
   profile or week.

## Re-tiering from the data

If the data suggests a skill or agent should move tiers:
1. Edit `~/.dotfiles/claude-code-shared/resources/model-tiers.json` (skills map for skills, agents map for agents).
2. `python3 ~/.dotfiles/claude-code-shared/scripts/sync-model-tiers.py --apply`
3. Full tiering docs: `~/.dotfiles/claude-code-shared/resources/model-tiers.md`

## Notes

- Cost is an estimate (list prices; subagent tokens are not folded in).
- Adherence is only meaningful for sessions after the tiering rollout (older runs
  used the session model).
- Profiles: office = `~/.cco`, personal = `~/.cch`. Default scans both.

<!-- learning-capture:start -->
## Learning Capture

**Default: write nothing.** Most runs record nothing. Only proceed if an observable
correction-event occurred this run — a tool failure you had to work around, a backtrack,
a user correction, an instruction gap, or redundant work you repeated.

### Step 1 — assess whether a correction-event occurred

If no correction-event: stop here. Do not call the judge. Do not call the writer.

### Step 2 — build a candidate entry

Construct this JSON object (do not include schema_version or timestamp; the writer injects them):

```json
{
  "skill": "<this skill's slug, e.g. debug>",
  "trigger": "<tool_failure | backtrack | user_correction | instruction_gap | redundant_effort | uncategorized>",
  "trigger_label": "<snake_case label if trigger == uncategorized, else null>",
  "evidence": "<WHAT happened this run. Observable, run-specific. For aggregated events (redundant_effort, backtrack, or any tried-N-times observation) list discrete quoted transcript anchors — not a bare count. The judge counts len(anchors).>",
  "learning": "<WHY it happened and the general reusable rule that must hold beyond this run. If this sentence only describes this run it belongs in evidence, not here.>",
  "suggested_fix": "<the concrete skill or script edit that would prevent recurrence, or null>"
}
```

Enumerate-discrete-anchors: for any aggregated observation, evidence must quote each
individual anchor explicitly. Example — correct: "Ran Glob three times: step 2 ('no
results'), step 5 ('no results'), step 8 ('found debug.jsonl')." Incorrect: "Ran Glob
three times without finding the file."

### Step 3 — grounding gate

Spawn the `learning-grounding-judge` agent (`subagent_type: learning-grounding-judge`,
model: haiku). Pass it:

```
## Entry
<candidate entry JSON>

## Transcript path
<absolute path to the session transcript file>
```

The agent returns `{"grounded": true|false, "reason": "..."}`.

### Step 4 — write or discard

If `grounded: true`:
```bash
echo '<entry JSON>' | python ~/.dotfiles/claude-code-shared/scripts/log-learning.py
```

If `grounded: false`: write nothing. The agent's reason explains what anchor was missing.
<!-- learning-capture:end -->
