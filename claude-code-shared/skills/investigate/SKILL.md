---
name: investigate
description: >
  Investigates a question, claim, external signal, or incident by routing it to
  the investigator orchestrator agent (Opus tier), which decomposes it into
  sub-claims, routes each to the appropriate source, and returns a schema-valid
  investigation-result with a unified verdict and merged evidence.
model: haiku
effort: low
---

Spawn the `investigator` agent (Opus tier) with the user's question or claim as-is. Return the raw investigation-result JSON to the caller.

## How to invoke

Use the Agent tool with `subagent_type: investigator`. Pass the full question or claim as provided by the user. Include `cwd` if the investigation involves codebase claims.

**Example — question form:**

```
Agent({
  subagent_type: "investigator",
  prompt: "question: Was the egress hook regression introduced in PR #204?\ncwd: /path/to/repo"
})
```

**Example — claim form:**

```
Agent({
  subagent_type: "investigator",
  prompt: "claim: The feature flag was disabled before the incident on 2026-08-10."
})
```

Return the raw investigation-result JSON from the agent to the caller.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `investigate`.
<!-- skill-done: investigate -->
<!-- learning-capture:end -->
