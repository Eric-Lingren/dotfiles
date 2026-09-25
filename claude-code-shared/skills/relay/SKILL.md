---
name: relay
description: >
  Channel-agnostic egress orchestrator for reply tasks. Reads the task file produced by
  /pr-revise, determines the target channel for each reply task from reply_url, presents
  combined drafts for final HITL approval, then delegates each approved draft to the
  appropriate channel adapter under agents/egress/. Use when dispatch-tasks routes the
  reply branch, or the user invokes /relay <task-file>.
model: sonnet
effort: medium
invokedBy: both
---

# Relay

Channel-agnostic egress orchestrator for the PR-feedback pipeline. `/pr-revise` writes
`reply` tasks into a task file; `/dispatch-tasks` routes the reply branch here after the
code branch lands. Relay determines which channel each reply belongs to from `reply_url`,
presents combined drafts for HITL approval, then delegates each approved reply to the
appropriate channel adapter under `agents/egress/`. Channel-specific mechanics —
commit permalink construction, thread keying, and future live write-back — live in the
adapter, not here.

**Live posting.** The GitHub adapter (`post-github`) posts live via `gh api`. Other channel
adapters (Linear, Slack) are copy-only stubs until wired for live write-back. relay tracks
each outcome (posted / skipped / failed / copy-only) and prints a result summary at the end.

## Contract

**Format:** task file — see `contracts/task-contract.md` (schema_version `"2"`)
**Role:** consumer (reads `reply` tasks; routes to channel adapters under `agents/egress/`)

**Step-0 — validate input before processing:**
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  --instance ~/.dotfiles/claude-code-shared/contracts/task-schema.json \
  <input-path>
```
On non-zero exit: STOP. Report stderr to the user. Do not process the file.

## Process

### 1. Load the task file

Use the path argument (from `/dispatch-tasks` or the user). Run Step-0 validation, then
read the file.

Select eligible items: `task_type == "reply"` with `status` of `not_started` (skip `done`,
`merged`, `blocked`). For each reply task, if `blocked_by` names a code task whose status
is not `done`/`merged`, the item is **not ready** — skip it and note it for the summary.
The fix has not landed; the reply belongs in a later run.

### 2. Determine channel for each eligible reply task

For each eligible task, inspect `reply_url` to determine the target channel adapter:

| reply_url domain    | Channel adapter                          |
|---------------------|------------------------------------------|
| `github.com`        | `agents/egress/github/post-github.md`    |
| `linear.app`        | `agents/egress/linear/post-linear.md`    |
| (other / missing)   | Warn the user; skip the task             |

Also read the blocking code task's `commit` and `pr` fields. These are passed to the channel
adapter so it can construct channel-specific formatting (e.g. commit permalink for GitHub).
relay does not construct commit permalinks directly — that is channel-specific logic owned
by each adapter.

### 3. Present for final HITL approval

For each eligible task, build the approval display. If the task carries both
`original_comment_body` and `original_comment_author`, show the original comment above the
draft:

```
── T-0002 · Reply: msw hook mocks ──
Channel: github (post-github)
Thread: <reply_url>

── Original comment by @<original_comment_author> ──
"<original_comment_body>"

── Your draft reply ──
<reply_body>
Commit reference: <commit SHA — will be formatted as permalink by the adapter>
```

If either `original_comment_body` or `original_comment_author` is absent, omit the
original-comment block and show only the draft:

```
── T-0002 · Reply: msw hook mocks ──
Channel: github (post-github)
Thread: <reply_url>
DRAFT:
<reply_body>
Commit reference: <commit SHA — will be formatted as permalink by the adapter>
```

Ask the user to approve, edit, or skip each draft. Apply their edits to the printed copy.
This is the content review gate — the reply text is locked in here.

**After the user approves the content**, show a second confirmation gate before posting:

```
This will post to <reply_url>. Proceed? (y/n)
```

Only proceed to step 4 if the user confirms with `y`. If the user answers `n`, treat this
task as skipped and record it as `skipped (user declined send)` in the results table.

### 4. Delegate each approved draft to the channel adapter

For each task that passed both approval gates, delegate to the resolved channel adapter. Pass:

- `draft` — the approved reply_body
- `target` — the reply_url (GitHub PR comment URL, etc.)
- `commit` — the blocking task's commit SHA (may be null)
- `pr` — the blocking task's PR URL (may be null)
- `thread_id` — the thread node id or database id (present only when task carries it)
- `thread_id_type` — `"graphql_node_id"` or `"database_id"` (disambiguates thread_id)

The channel adapter returns a schema-valid egress-result with `status: "posted"`,
`"copy-only"`, or `"failed"`. Record the result for the step 5 summary.

**On failure:** if the egress-result has `status: "failed"`, show the error and prompt the
user:

```
Post failed: <error details>

Options:
  1. Retry
  2. Skip this task
  3. Abort remaining tasks
```

- **Retry (1):** re-delegate to the same adapter with the same inputs. Repeat until the
  post succeeds, the user chooses skip, or the user chooses abort.
- **Skip (2):** record this task as `failed` in the results and continue to the next task.
- **Abort (3):** stop processing remaining tasks. Record all unprocessed tasks as
  `skipped (aborted)` in the results.

### 5. Result summary

After all tasks are processed, print a per-task result table followed by totals:

```
── Relay Results ──
T-0002 · Reply: msw hook mocks: posted → https://github.com/owner/repo/pull/42#issuecomment-123
T-0003 · Reply: auth token: skipped (user skipped)
T-0004 · Reply: cache invalidation: failed → <error message>

Posted: 1 | Skipped: 1 | Failed: 1 | Copy-only: 0
```

Count each outcome:
- **posted** — adapter returned `status: "posted"`
- **skipped** — user skipped at content approval, declined the send confirmation, task was
  not ready (blocked_by not done), or unprocessed due to abort
- **failed** — adapter returned `status: "failed"` and user chose skip (or abort triggered)
- **copy-only** — adapter returned `status: "copy-only"` (non-GitHub channel stubs)

For `copy-only` tasks the draft was printed by the adapter for manual paste; include those
in the copy-only count and note them in the table as `copy-only → <draft printed above>`.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `relay`.
<!-- skill-done: relay -->
<!-- learning-capture:end -->
