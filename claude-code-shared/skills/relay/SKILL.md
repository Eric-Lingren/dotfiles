---
name: relay
description: >
  STUB. Reply egress skill for non-code PR feedback items (questions, discuss, nit). Posts
  threaded GitHub replies and resolves threads. Deferred until write-back UX and error cases
  are properly designed. v1 behavior is notify-only (inline in revise-pr).
model: sonnet
effort: medium
---

This skill is a stub. It is not yet functionally implemented.

It serves as a wiring anchor in `skill-pipeline.json` for the revise-pr pipeline egress.
When built, `relay` will post threaded GitHub replies for non-code items and resolve threads.
v1 inline behavior (notify-only print) lives inside `revise-pr` Step 9 until this skill is built.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `relay`.
<!-- skill-done: relay -->
<!-- learning-capture:end -->
