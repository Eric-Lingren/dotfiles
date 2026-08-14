---
name: fact-check
description: >
  RETIRED. Use /investigate instead. The fact-checker agent and its 6-tier verdict scale
  have been superseded by the investigation pipeline (investigator-web leaf agent +
  investigation-result contract).
model: sonnet
effort: medium
---

# Fact-Check — Retired

This skill has been retired. Use `/investigate` instead.

The fact-checking capability has been migrated into the investigation pipeline:

- **Leaf agent:** `agents/investigators/investigator-web.md` — accepts a sub-claim, searches the web, and emits an `investigation-result` contract.
- **Skill:** `/investigate` — the entry point for external-signal investigation (Sentry, Slack, Datadog, open questions).

The old 6-tier verdict scale (TRUE / MOSTLY_TRUE / PARTLY_TRUE / MOSTLY_FALSE / FALSE / UNVERIFIABLE) is replaced by the 4-verdict `investigation-result` contract (VERIFIED_TRUE / VERIFIED_FALSE / INSUFFICIENT_EVIDENCE / CONTESTED), documented in `contracts/investigation-result-contract.md`.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `fact-check`.
<!-- skill-done: fact-check -->
<!-- learning-capture:end -->
