---
name: investigate
description: >
  STUB. Standalone external-signal explorer. Takes a Sentry ticket, Slack thread, Datadog
  signal, or open question without context and investigates it. Distinct from vet (which
  verifies flagged code claims). Part of the investigation skill family.
model: sonnet
effort: high
---

This skill is a stub. It is not yet functionally implemented.

It serves as a wiring anchor in `skill-pipeline.json`. When built, `investigate` will
explore unknown external signals (Sentry, Slack, Datadog) and surface actionable findings.
Methodology is similar to `vet` but operates on external-signal domain rather than code claims.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `investigate`.
<!-- skill-done: investigate -->
<!-- learning-capture:end -->
