---
name: browser-check-result
description: JSON contract returned by the browser-checker agent to its caller (run-tasks, debug). Defines the three statuses, all fields, and how each status maps to caller behavior.
---

# Browser Check Result Contract

The browser-checker agent returns a single JSON object on stdout. All consumers (run-tasks, debug) parse this contract. Do not define the schema inline in skill or agent files.

## Schema

```json
{
  "status": "pass" | "fail" | "skipped",
  "url": "string — the full URL that was checked",
  "assertions": [
    {
      "description": "string — the observable behavior that was checked",
      "passed": true | false,
      "detail": "string? — failure detail, screenshot excerpt, or DOM excerpt; omitted on pass"
    }
  ],
  "console_errors": ["string — each console.error / unhandled rejection captured during the run"],
  "artifacts_dir": "string | null — absolute path to the run dir (docs/browser-checks/YYYYMMDD-HHMM-<slug>/); null on pass (dir is cleaned on success)",
  "screenshot": "string | null — absolute path to screenshot.png inside artifacts_dir; null if no screenshot was taken",
  "skipped_reason": "string | null — human-readable reason when status is skipped; null otherwise"
}
```

## Field definitions

| Field | Always present | Notes |
|---|---|---|
| `status` | yes | `"pass"`, `"fail"`, or `"skipped"` |
| `url` | yes | Full URL: `base_url + url_path` |
| `assertions` | yes | Empty array when `status` is `"skipped"` |
| `console_errors` | yes | Empty array if none captured |
| `artifacts_dir` | yes | `null` on pass (cleaned up); absolute path on fail or skipped |
| `screenshot` | yes | `null` if no screenshot taken (pass, or skipped) |
| `skipped_reason` | yes | `null` unless `status` is `"skipped"` |

## Statuses

### `"pass"`

All assertions evaluated to `true`. No `console_errors` were captured (or any captured are informational only — caller may inspect).

**Caller behavior:** task may proceed to `done`. Clean the `artifacts_dir` (the agent already does this on success — caller need not act).

### `"fail"`

One or more assertions evaluated to `false`, or the page threw an unhandled error that prevented assertion evaluation.

**Caller behavior:**
1. Log the failing assertions and any `console_errors`.
2. Attempt to fix the source code.
3. Re-spawn the browser-checker with the same spec.
4. Repeat up to a hard cap of 3 total attempts. Bail early if two consecutive runs produce identical failures (no-progress detection).
5. On cap or no-progress bail: mark task `blocked`, pause for HITL. Surface: the failing assertions, the iteration log, and the `screenshot` path from `artifacts_dir`.

### `"skipped"`

The check could not run. Either the Playwright module was unavailable, or the server could not be reached after the startup timeout.

**Caller behavior:** do not block the task. Report `skipped_reason` in the run summary and move on. A skipped result is not a failure.

---

## Example payloads

### Pass

```json
{
  "status": "pass",
  "url": "http://localhost:5173/dashboard",
  "assertions": [
    { "description": "Page title is 'Dashboard'", "passed": true },
    { "description": "Nav link 'Reports' is visible", "passed": true }
  ],
  "console_errors": [],
  "artifacts_dir": null,
  "screenshot": null,
  "skipped_reason": null
}
```

### Fail

```json
{
  "status": "fail",
  "url": "http://localhost:5173/dashboard",
  "assertions": [
    { "description": "Page title is 'Dashboard'", "passed": true },
    {
      "description": "Nav link 'Reports' is visible",
      "passed": false,
      "detail": "Element with text 'Reports' not found after 5000 ms. DOM snapshot: <nav>...</nav>"
    }
  ],
  "console_errors": [
    "TypeError: Cannot read properties of undefined (reading 'map') at NavBar.tsx:42"
  ],
  "artifacts_dir": "/Users/eric/project/docs/browser-checks/20260602-1430-dashboard-nav",
  "screenshot": "/Users/eric/project/docs/browser-checks/20260602-1430-dashboard-nav/screenshot.png",
  "skipped_reason": null
}
```

### Skipped

```json
{
  "status": "skipped",
  "url": "http://localhost:5173/dashboard",
  "assertions": [],
  "console_errors": [],
  "artifacts_dir": null,
  "screenshot": null,
  "skipped_reason": "Playwright module not found in project node_modules or global install"
}
```
