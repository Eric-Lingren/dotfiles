---
name: answer
description: >
  Accepts a question (paste of Slack message text or link), routes it through
  the investigator orchestrator for claim verification, then passes the
  investigation-result to answer-composer to produce a voice-matched Slack
  reply for manual paste. The skill is a thin doorway: no verification or
  composition logic lives here.
model: haiku
effort: low
invokedBy: human
---

Spawn the `investigator` agent with the user's question. Pass the returned investigation-result and the original question to the `answer-composer` agent. Return the composed Slack reply as-is.

## How to invoke

**Step 1 — Investigate**

Use the Agent tool with `subagent_type: investigator`. Pass the user's question verbatim.

```
Agent({
  subagent_type: "investigator",
  prompt: "question: <user's question verbatim>"
})
```

**Step 2 — Compose**

Use the Agent tool with `subagent_type: answer-composer`. Pass the full investigation-result from step 1 and the original question.

```
Agent({
  subagent_type: "answer-composer",
  prompt: "investigation_result: <JSON from step 1>\nquestion: <original question>"
})
```

**Step 3 — Return**

Return the plain text Slack reply from answer-composer verbatim. Do not edit, reformat, or add any framing text.

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `answer`.
<!-- skill-done: answer -->
<!-- learning-capture:end -->
