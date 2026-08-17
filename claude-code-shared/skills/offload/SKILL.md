---
name: offload
description: >
  Offload a skill invocation to a remote cloud agent. Accepts a target skill name and
  optional input content; looks up the skill's model and effort from model-tiers.json;
  spawns an Agent with isolation: 'remote' and the resolved model; instructs the remote
  agent to run the target skill at the looked-up effort level and return the full output
  as text; then writes the result to docs/seeds/ (for seeds) or docs/tasks/ (for tasks).
model: sonnet
effort: medium
invokedBy: human
---

# Offload

Runs a target skill in a remote cloud agent and writes the output to the local workspace.

## Inputs

```
/offload <target-skill> [input-content]
```

- `<target-skill>` — the name of the skill to invoke remotely (e.g. `to-seed`, `to-tasks`).
- `[input-content]` — optional content to pass as input to the remote skill. If omitted,
  compress the current conversation context into a brief (a few hundred words) and use that
  as input.

## Process

### 1. Parse args

Read the user's message. Extract `target-skill` and any `input-content` exactly as provided.

If no target skill is given, print the invocation form above and stop.

If no `input-content` was provided, compress the current conversation to a brief:
- Include the topic, key decisions, and any file paths or data needed by the target skill.
- Keep it under 400 words — enough context for a cold agent to run the skill without this session.

### 2. Look up model and effort from model-tiers.json

Read `~/.dotfiles/claude-code-shared/resources/model-tiers.json`.

Find the tier for `target-skill` in the `skills` section. If the skill is not listed, use
the `default` tier.

Resolve the tier to `model` and `effort` values from the `tiers` section.

Example: `"to-seed": "T3"` resolves to `model: "sonnet"`, `effort: "high"`.

### 3. Spawn the remote agent

Spawn an Agent with:

```
isolation: "remote"
model: <resolved model>
description: "Offloaded <target-skill> run"
prompt: <see template below>
```

**Prompt template:**

```
You are running the /<target-skill> skill at effort level: <resolved effort>.

## Input

<input-content or compressed context brief>

## Instructions

1. Load and execute the /<target-skill> skill as instructed in its SKILL.md.
2. Produce the full output the skill would normally write to a file.
3. Return the COMPLETE file content as plain text in your final response — no truncation,
   no summary, no fences around the whole thing (only fences inside the content if the
   skill uses them). The caller will write the text to disk exactly as returned.

Effort level reminder: work at <resolved effort> effort — <effort description>.
```

Effort descriptions by level:
- `low` — fast lookup, minimal reasoning, answer directly.
- `medium` — mechanical execution, well-defined scope, no open-ended exploration.
- `high` — context-aware, standard depth.
- `xhigh` — deep reasoning, architecture-level thinking.

### 4. Receive output and write to disk

Receive the agent's text response (the full file content).

Determine the output directory:
- If the target skill produces **seeds** (e.g. `to-seed`): write to `docs/seeds/`
- If the target skill produces **tasks** (e.g. `to-tasks`): write to `docs/tasks/`
- Otherwise: write to `docs/offload-output/` and create the directory if needed.

Generate a filename:

```bash
~/.dotfiles/claude-code-shared/scripts/doc-filename.sh <target-skill>-offload json
```

Write the agent's response verbatim to that path.

Report the output path to the user.
