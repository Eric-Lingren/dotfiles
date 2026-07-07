---
name: relay
description: >
  STUB. Reply egress skill for PR feedback items. Posts threaded GitHub replies and resolves
  threads. Deferred until write-back UX and error cases are properly designed. Until built,
  revise-pr Step 9 drafts copy-only reply text inline (no external calls); relay owns the posting.
model: sonnet
effort: medium
---

This skill is a stub. It is not yet functionally implemented.

It serves as a wiring anchor in `skill-pipeline.json` for the revise-pr pipeline egress.
When built, `relay` will post threaded GitHub replies and resolve threads. Until then, `revise-pr`
Step 9 drafts copy-only reply text inline (terminal print, zero external calls) for every substantive
item, and prints a no-external-calls banner so the user can paste manually and verify nothing was sent.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `relay`.
<!-- skill-done: relay -->
<!-- learning-capture:end -->
