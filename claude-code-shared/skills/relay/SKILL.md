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
---

# Relay

Channel-agnostic egress orchestrator for the PR-feedback pipeline. `/pr-revise` writes
`reply` tasks into a task file; `/dispatch-tasks` routes the reply branch here after the
code branch lands. Relay determines which channel each reply belongs to from `reply_url`,
presents combined drafts for HITL approval, then delegates each approved reply to the
appropriate channel adapter under `agents/egress/`. Channel-specific mechanics —
commit permalink construction, thread keying, and future live write-back — live in the
adapter, not here.

**Copy-only status.** relay delegates to copy-only channel adapter stubs — nothing is
posted until the adapters are wired for live write-back. Today relay assembles each draft,
presents it for approval, and delegates to the adapter for manual-paste output.

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

Print each combined draft grouped by thread:

```
Reply drafts (copy-only — nothing posted yet):

── T-0002 · Reply: msw hook mocks ──
Channel: github (post-github)
Thread: <reply_url>
DRAFT:
<reply_body>
Commit reference: <commit SHA — will be formatted as permalink by the adapter>
```

Ask the user to approve, edit, or skip each draft. Apply their edits to the printed copy.
This is the final review gate the reply content gets before it would be posted.

### 4. Delegate each approved draft to the channel adapter

For each user-approved reply task, delegate to the resolved channel adapter. Pass:

- `draft` — the approved reply_body
- `target` — the reply_url (GitHub PR comment URL, etc.)
- `commit` — the blocking task's commit SHA (may be null)
- `pr` — the blocking task's PR URL (may be null)
- `thread_id` — the thread node id or database id (present only when task carries it)
- `thread_id_type` — `"graphql_node_id"` or `"database_id"` (disambiguates thread_id)

The channel adapter handles all channel-specific mechanics: commit permalink construction,
thread keying, and (when live write-back ships) the actual API call.

### 5. No-external-calls banner

After all drafts, print this verbatim so the user can confirm nothing was sent:

```
────────────────────────────────────────────────────────────
NO EXTERNAL CALLS MADE.
  - 0 GitHub comments posted
  - 0 threads resolved
  - 0 task statuses changed
Copy above is DRAFT only. Review, edit, and paste manually.
────────────────────────────────────────────────────────────
```

These counts are literal invariants while relay's channel adapters are copy-only stubs.
When posting ships, each adapter will post the approved reply, resolve the thread, and
relay will set the task `status` to `done` with the posted comment URL.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `relay`.
<!-- skill-done: relay -->
<!-- learning-capture:end -->
