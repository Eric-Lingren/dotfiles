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

## Step 1 — Detect link input

If the user's input is (or contains) a URL, fetch the content first to derive the question or claim.

**Slack permalink** (`https://app.slack.com/...` or `https://*.slack.com/archives/...`):
- Use `mcp__claude_ai_Slack__slack_read_thread` with the channel and message timestamp extracted from the URL.
- Slack permalink format: `.../archives/<channel_id>/p<ts_digits>` where ts = `<10digits>.<6digits>`.
- Read the thread. Summarise the core question or claim being asked. That summary becomes the investigation input.

**GitHub URL** (issue, PR, comment):
- Use `gh issue view` or `gh pr view` via Bash to fetch the body and comments.
- Extract the core question or claim. That becomes the investigation input.

**Generic URL**:
- Use `WebFetch` to retrieve the page content.
- Extract the core question or claim from the content.

If the input is already a plain question or claim (no URL), skip Step 1 entirely.

## Step 2 — Spawn the investigator

Use the Agent tool with `subagent_type: investigator`. Pass the derived (or original) question or claim. Include `cwd` if the investigation involves codebase claims.

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

**Example — Slack link input:**

User pastes `https://acme.slack.com/archives/C012AB3CD/p1723660012345678`.
1. Parse: channel=`C012AB3CD`, ts=`1723660012.345678`.
2. Call `slack_read_thread` to fetch thread content.
3. Derive question from thread (e.g., "Was the deploy on 2026-08-14 the cause of the latency spike?").
4. Pass derived question to investigator.

Return the raw investigation-result JSON from the agent to the caller.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `investigate`.
<!-- skill-done: investigate -->
<!-- learning-capture:end -->
