---
name: vet
description: >
  STUB. Diligence executor for verifying PR claims against code. Takes a flagged claim and
  code pointers, verifies against actual code, and returns confirmed/false_flag/not_an_escape
  verdict. Slots into the mandatory diligence gate inside revise-pr when built.
model: sonnet
effort: high
---

This skill is a stub. It is not yet functionally implemented.

It serves as a wiring anchor in `skill-pipeline.json` for the revise-pr diligence gate.
When built, `vet` will automate what is currently a manual step: take a flagged claim plus
code pointers, verify the claim against actual code, and return a diligence verdict.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `vet`.
<!-- skill-done: vet -->
<!-- learning-capture:end -->
