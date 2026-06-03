# Runner Result Contract

All runner agents (lint-runner, test-runner, e2e-runner) return a single JSON verdict object. The verdict is the agent's entire response — callers parse it directly.

**Critical rule:** A `skipped` status means the check could not run (no tool configured, no command resolved). It must be surfaced to the user. Never treat `skipped` as green.

## Verdict shape

```json
{
  "status": "pass",
  "check_type": "lint",
  "workspace": ".",
  "command": "biome check --reporter=json .",
  "summary": "0 errors, 0 warnings",
  "counts": {
    "errors": 0,
    "warnings": 0,
    "fixable": 0
  },
  "violations": [],
  "skipped_reason": null
}
```

## Field reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | `"pass"` \| `"fail"` \| `"skipped"` \| `"error"` | yes | Outcome of the check. |
| `check_type` | `"lint"` \| `"format"` \| `"typecheck"` \| `"test"` \| `"e2e"` | yes | Category of check. |
| `workspace` | string | yes | Relative workspace path, e.g. `"."`, `"client"`, `"app"`. |
| `command` | string \| null | yes | The command that was run. `null` only when `status` is `"skipped"`. |
| `summary` | string | yes | Human-readable one-line summary. |
| `counts` | object | yes | Check-type-specific counts (see below). |
| `violations` | array | yes | Lint/format/typecheck findings. Empty array for test/e2e. |
| `failures` | array | no | Test/e2e failures. Present only in test-runner and e2e-runner verdicts. |
| `skipped_reason` | string \| null | yes | Non-null only when `status` is `"skipped"`. |

### `counts` by check type

**Lint / format / typecheck:**
```json
{ "errors": 3, "warnings": 2, "fixable": 1 }
```

**Test / e2e:**
```json
{ "passed": 10, "failed": 2, "skipped": 1 }
```

All count values are integers >= 0.

### `violations` entries (lint / format / typecheck)

```json
{
  "file": "src/index.ts",
  "line": 10,
  "col": 5,
  "rule": "noUnusedVars",
  "severity": "error",
  "message": "Variable 'x' is never used."
}
```

| Field | Type | Notes |
|-------|------|-------|
| `file` | string | Relative path from workspace root. |
| `line` | integer \| null | 1-indexed line number. `null` if unavailable. |
| `col` | integer \| null | 1-indexed column number. `null` if unavailable. |
| `rule` | string \| null | Rule or diagnostic code. `null` if unavailable. |
| `severity` | `"error"` \| `"warning"` | Severity level. |
| `message` | string | Human-readable description. |

### `failures` entries (test / e2e)

```json
{
  "test_name": "renders login form",
  "file": "src/components/__tests__/Login.test.tsx",
  "line": 42,
  "assertion_message": "Expected 'Login' to be visible",
  "top_user_frame": "Login.test.tsx:42:5"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `test_name` | string | Full test name (suite + test). |
| `file` | string | Relative path from workspace root. |
| `line` | integer \| null | Line of the failing assertion. |
| `assertion_message` | string | The assertion error message. No full stack traces. |
| `top_user_frame` | string \| null | `file:line:col` of the top frame in user code. |

## Status rules

- **`pass`** — command exited 0, no errors.
- **`fail`** — command found issues (errors or test failures). `counts.errors > 0` or `counts.failed > 0`.
- **`skipped`** — no command was resolved (tool not installed, config absent). Set `command: null`, `skipped_reason` non-null. Never return `pass` when skipped.
- **`error`** — the command itself failed to run (subprocess crash, parse error). Include the error detail in `summary`.

## Schema

The canonical schema and contract have moved to `contracts/`. See `contracts/runner-result-contract.md` and `contracts/runner-result-schema.json`.
