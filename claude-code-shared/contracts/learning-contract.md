# Learning Contract

**Format name:** Learning entry file (`claude-code-shared/learnings/<skill>.jsonl`)
**Schema:** `contracts/learning-schema.json` (schema_version: `"1"`)
**Writer:** `scripts/log-learning.py` — the only path for writing entries; skills never write JSONL directly.

## Producers

All 24 shared skills. Plugin skills (caveman, chrome-devtools) are excluded.

- `skills/cc-usage-analytics/`
- `skills/clean-scaffolding/`
- `skills/code-review/`
- `skills/debug/`
- `skills/fact-check/`
- `skills/find-work/`
- `skills/grill-me/`
- `skills/grill-with-docs/`
- `skills/handoff/`
- `skills/how-to/`
- `skills/improve-codebase-architecture/`
- `skills/improve-component/`
- `skills/improve-skill/`
- `skills/prototype/`
- `skills/register-skill/`
- `skills/run-task-followups/`
- `skills/run-tasks/`
- `skills/tasks-to-linear/`
- `skills/tdd/`
- `skills/tldr-tech/`
- `skills/to-e2e-tasks/`
- `skills/to-prd-html/`
- `skills/to-seed/`
- `skills/to-tasks/`

New skills registered via `register-skill` are added to this list automatically.

## Consumers

- `skills/improve-skill/` — future consumer; reads per-skill JSONL files, applies `suggested_fix` candidates, and owns promoting recurring `uncategorized` trigger_labels into named trigger values.

## Schema file

[learning-schema.json](learning-schema.json)

## Storage layout

```
claude-code-shared/
  learnings/
    debug.jsonl
    run-tasks.jsonl
    to-seed.jsonl
    ...
```

One JSONL file per skill. Each line is a complete, schema-valid JSON object. Created on first write by `log-learning.py`. Committed to the dotfiles repo like all other shared artifacts.

## Trigger vocabulary

The `trigger` field is an **open vocabulary** gated by grounding, not enum-match. A learning is admissible only if an observable transcript artifact proves the correction-event happened. Most runs record nothing.

| Value | Meaning |
|-------|---------|
| `tool_failure` | A tool call returned an error or unexpected result that forced a correction |
| `backtrack` | The skill reversed a step it had already taken |
| `user_correction` | The user explicitly corrected the skill's output or approach |
| `instruction_gap` | The skill lacked a rule or instruction needed to handle the situation |
| `redundant_effort` | The skill repeated work it had already done (extra searches, re-reads, retries) |
| `uncategorized` | A legitimate correction-event that does not fit any named value. Requires a `trigger_label` (free-text snake_case). Recurring labels are promoted to named trigger values. |

**No ungrounded escape hatch.** `uncategorized` entries still require a verified transcript anchor. There is no "other" value that bypasses grounding.

## Enumerate-discrete-anchors rule

For any entry whose evidence aggregates or counts repeated events (e.g. `redundant_effort`, `backtrack`, or any "tried N times" observation), the `evidence` field **must list the discrete transcript anchors** rather than asserting a bare count.

Correct: `"Ran Glob for '*.jsonl' three times: first at step 2 ('no results'), again at step 5 ('no results'), again at step 8 ('found learnings/debug.jsonl')."`

Incorrect: `"Ran Glob for '*.jsonl' three times without finding the file."`

The count is derived as `len(anchors)` by the grounding judge. This keeps the haiku judge in verification (not free counting) range.

## End-of-run flow

```
skill builds candidate entry (trigger, trigger_label, evidence, learning, suggested_fix, skill name)
  → spawns learning-grounding-judge with entry JSON + session transcript path
  → grounded=true: echo entry JSON | python ~/.dotfiles/claude-code-shared/scripts/log-learning.py
  → grounded=false or no correction-event: write nothing
```

`log-learning.py` injects `timestamp` and `schema_version` server-side before validation and append. Skills never supply those fields.

## Trigger_label promotion

When an `uncategorized` label recurs across multiple runs, it is a candidate for promotion to a named trigger value. Promotion is done by editing this contract and `learning-schema.json` to add the new enum value. `improve-skill` owns this process.
