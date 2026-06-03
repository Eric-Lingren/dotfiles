# Runner Result Contract

**Format name:** Runner verdict (inline JSON response)
**Schema:** `contracts/runner-result-schema.json` (schema_version: `"1"`)

## Producers

- `agents/lint-runner.md` — runs lint/format checks, returns verdict
- `agents/test-runner.md` — runs unit/integration tests and typecheck, returns verdict
- `agents/e2e-runner.md` — runs Playwright e2e suite, returns verdict

## Consumers

- `skills/run-tasks/` — spawns runners in parallel, gates task done on all verdicts passing

## Status rules

- **`pass`**: command exited 0, no errors
- **`fail`**: command found issues (`counts.errors > 0` or `counts.failed > 0`)
- **`skipped`**: no command resolved (tool not installed, config absent). Set `command: null`, `skipped_reason` non-null. Never treat skipped as green.
- **`error`**: the command itself crashed (subprocess error, parse failure). Include detail in `summary`.

## Critical rule

A `skipped` verdict must be surfaced to the user. Never treat `skipped` as a pass.

## Schema file

[runner-result-schema.json](runner-result-schema.json)
