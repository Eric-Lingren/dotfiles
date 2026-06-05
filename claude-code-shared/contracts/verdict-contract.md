---
name: verdict-contract
description: Contract for judge agent output. Each judge returns a single verdict object. Single source of truth for orchestrator parsing and judge instructions.
---

# Verdict Contract

**Schema:** `verdict-schema.json`
**Producer:** persona-judge agent (spawned 3x per refutation)
**Consumer:** to-seed verification stage orchestrator

## Output rule

**Judges output only JSON, never prose or questions.** The entire response must be a single valid JSON object. No preamble, no explanation, no markdown fences.

## Normal form

```json
{
  "verdict": "upheld",
  "reason": "The transcript span cited by the persona directly contradicts the seed's claim at decisions[2]."
}
```

or

```json
{
  "verdict": "rejected",
  "reason": "No span in the transcript supports the refutation; the claim is consistent with the discussion at line 47."
}
```

`verdict` must be exactly `"upheld"` or `"rejected"`. No other values are valid.

## Error form

On unrecoverable failure, the judge returns a single error object:

```json
{
  "error": "could not read transcript file",
  "details": "path /Users/eric/.claude/projects/... does not exist"
}
```

## Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `verdict` | string | yes (normal) | `"upheld"` or `"rejected"` |
| `reason` | string | yes (normal) | One sentence citing the specific span or its absence |
| `error` | string | yes (error) | Short description of the failure |
| `details` | string | no (error) | Optional additional context |

## Adjudication

Three judge instances run per refutation. The orchestrator collects all three verdicts and applies a flat 2-of-3 majority:
- 2 or 3 `upheld` → refutation is upheld; apply it to the draft seed
- 2 or 3 `rejected` → refutation is rejected; no change to the seed
- If 2 or more judge instances return error-form objects for the same refutation, skip that refutation and record the failure

The orchestrator validates each verdict against this schema. On a parse mismatch, it retries the judge once.
