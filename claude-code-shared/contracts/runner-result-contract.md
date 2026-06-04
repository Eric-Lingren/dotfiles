# Runner Result Contract

JSON verdict returned by `lint-runner` and `test-runner` agents. The caller (run-tasks) inspects `status` to gate task completion.

## Schema

See `runner-result-schema.json` in this directory for the machine-readable schema.

## Status enum

| Value | Meaning | run-tasks gate |
|-------|---------|----------------|
| `pass` | All checks passed. Tests passed, no typecheck errors, no lint violations. | Proceed |
| `fail` | One or more checks failed. Tests failed, typecheck errors present, or lint violations detected. | Block |
| `warn` | Checks technically ran but produced no meaningful result: 0 affected tests selected, no test command configured for this workspace, or a non-fatal issue. | Proceed (log warning) |
| `timeout` | The run exceeded the 180s wall-clock timeout. Entire process group was killed. | Block |
| `deps-missing` | Required dependencies absent: binary not found (e.g. `vitest` not in path), or `node_modules` missing. The test command would likely fail or produce nonsense if run. | Block |

**Never emit `skipped` or `error` as status values.** Use `warn` when no tests apply. Use `fail` when a command crashes. Use `deps-missing` when the runner binary or dependencies are absent.

## Counts object

```json
{
  "passed": 10,
  "failed": 2,
  "skipped": 1
}
```

- `passed`: Number of tests that passed (test-runner only; lint-runner returns 0).
- `failed`: Number of tests that failed OR number of lint violations (depending on runner).
- `skipped`: Number of tests skipped.

## Violations array

Each violation from the typecheck or lint runner:

```json
{
  "file": "src/index.ts",
  "line": 10,
  "col": 5,
  "rule": "TS2345",
  "severity": "error",
  "message": "Argument of type 'string' is not assignable to parameter of type 'number'."
}
```

## Failures array

Each failed test case (test-runner only):

```json
{
  "test_name": "Login > renders login form",
  "file": "src/__tests__/Login.test.tsx",
  "line": 42,
  "assertion_message": "Expected element to be visible",
  "top_user_frame": "Login.test.tsx:42:5"
}
```

## Full example

```json
{
  "status": "fail",
  "check_type": "test",
  "workspace": "client",
  "command": "vitest run --reporter=json",
  "summary": "2 failed, 10 passed, 1 skipped; 3 typecheck errors",
  "counts": {"passed": 10, "failed": 2, "skipped": 1},
  "violations": [
    {
      "file": "src/index.ts",
      "line": 10,
      "col": 5,
      "rule": "TS2345",
      "severity": "error",
      "message": "Argument of type 'string' is not assignable to parameter of type 'number'."
    }
  ],
  "failures": [
    {
      "test_name": "Login > renders login form",
      "file": "src/__tests__/Login.test.tsx",
      "line": 42,
      "assertion_message": "Expected element to be visible",
      "top_user_frame": "Login.test.tsx:42:5"
    }
  ],
  "skipped_reason": null
}
```
