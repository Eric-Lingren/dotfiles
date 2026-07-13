---
name: relay
description: >
  Reply egress for PR feedback. Consumes the `reply` tasks in a task file produced by /pr-revise,
  stitches the blocking code task's fixing commit into each draft, presents the combined drafts for
  final HITL approval, and (copy-only until fully built) prints them for manual paste. Posting
  threaded replies and resolving threads is deferred until write-back UX and error cases are designed.
  Use when dispatch-tasks routes the reply branch, or the user invokes /relay <task-file>.
model: sonnet
effort: medium
---

# Relay

Egress for the PR-feedback pipeline. `/pr-revise` writes `reply` tasks into a task file; `/dispatch-tasks` routes the reply branch here after the code branch lands. relay turns each reply task into **one combined comment** — the acknowledgement plus a permalink to the commit that fixed it — so a reviewer never gets a "here's the plan" comment followed by a separate "here's the commit" comment.

**Copy-only status.** relay does not yet post to GitHub or resolve threads. Those writes are deferred until the write-back UX and error cases are designed. Today relay assembles each combined draft, presents it for approval, and prints it for manual paste. Everything it needs to post later already lives in the task file (`reply_body`, `reply_url`, `thread_id`, `thread_id_type`, and the blocking task's `commit`), so no rework is needed when posting ships.

## Contract

**Format:** task file — see `contracts/task-contract.md` (schema_version `"2"`)
**Role:** consumer (reads `reply` tasks; will write back `status` on posted items once posting ships)

**Step-0 — validate input before processing:**
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  --instance ~/.dotfiles/claude-code-shared/contracts/task-schema.json \
  <input-path>
```
On non-zero exit: STOP. Report stderr to the user. Do not process the file.

## Process

### 1. Load the task file

Use the path argument (from `/dispatch-tasks` or the user). Run Step-0 validation, then read the file.

Select eligible items: `task_type == "reply"` with `status` of `not_started` (skip `done`, `merged`, `blocked`). For each reply task, if `blocked_by` names a code task whose status is not `done`/`merged`, the item is **not ready** — skip it and note it for the summary. The fix has not landed, so there is no commit to cite yet; the reply belongs in a later run.

### 2. Stitch the fixing commit into each draft

For each eligible reply task:
- If `blocked_by` names a code task, read that task's `commit` and `pr`:
  - `commit` present → append a fix-reference line to `reply_body`, e.g. `Fixed in <short-sha>.` as a permalink built from the repo/PR URL + full SHA (`<repo-url>/commit/<sha>`).
  - `commit` null but `pr` present → reference the PR instead: `Fixed in <pr-url>.`
  - neither present → omit the fix reference (push was declined upstream).
- Reply-only tasks (empty `blocked_by`) carry no fix reference by design.

Never fabricate a SHA. Use only what build-code recorded on the blocking task.

### 3. Present for final HITL approval

Print each combined draft grouped by thread:

```
Reply drafts (copy-only — nothing posted yet):

── T-0002 · Reply: msw hook mocks ──
Thread: <reply_url>
DRAFT:
<reply_body + stitched fix reference>
```

Ask the user to approve, edit, or skip each draft. Apply their edits to the printed copy. This is the final review gate the reply content gets before it would be posted.

### 4. No-external-calls banner

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

These counts are literal invariants while relay is copy-only. When posting ships, this step will post each approved reply under `thread_id` (keyed by `thread_id_type`), resolve the thread, set the reply task `status` to `done` with the posted comment URL, and replace this banner with a real post-count report.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `relay`.
<!-- skill-done: relay -->
<!-- learning-capture:end -->
