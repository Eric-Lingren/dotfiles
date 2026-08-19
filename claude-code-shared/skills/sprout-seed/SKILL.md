---
name: sprout-seed
description: >
  End-to-end unattended pipeline: converts a seed file into tasks, executes every
  AFK task via build-code, and returns a pr-code-review of the resulting diff —
  all without user interaction. Use when you want one command to go from seed to
  reviewed PR.
model: sonnet
effort: high
invokedBy: human
---

# Sprout Seed

Run the full seed-to-reviewed-PR pipeline unattended. Three skills execute in
sequence as isolated subagents; no HITL gates interrupt the chain.

## Invocation

```
/sprout-seed docs/seeds/my-feature.json
```

The argument is the path to a ready (non-draft) seed file.

## Architecture

Each skill runs as a **fresh-context subagent** spawned with the Agent tool —
never the Skill tool inline. Context flows only through file paths and text
captured from each agent's output. The session model orchestrates; it never
holds an agent's full trace.

Model and effort for each subagent come from
`~/.dotfiles/claude-code-shared/resources/model-tiers.json`:

| Skill          | Tier | Model  | Effort |
| -------------- | ---- | ------ | ------ |
| `to-tasks`     | T3   | sonnet | high   |
| `build-code`   | T3   | sonnet | high   |
| `pr-code-review` | T3 | sonnet | high   |

## Process

### Step 0: Resolve and validate the seed path

Read the seed file. Confirm `status` is `"ready"` — if it is `"draft"`, stop and
tell the user to resolve open threads before running sprout-seed.

Derive a branch name from the seed filename slug using the conventions in
`~/.dotfiles/claude-code-shared/resources/branching-strategy.md` (typically
`feat/<slug>`).

### Step 1: to-tasks — generate the task file

Spawn a **fresh** `to-tasks` agent using the Agent tool (not the Skill tool):

```
Agent(
  subagent_type="to-tasks",
  prompt=<see prompt template below>
)
```

**to-tasks subagent prompt template:**

```
You are running the to-tasks skill in fully unattended mode.

Seed path: <seed_path>
Branch name: <branch_name>  (use this exact name — do not ask)

Follow ~/.dotfiles/claude-code-shared/skills/to-tasks/SKILL.md exactly, with
these overrides for unattended operation:
- Use the seed path above directly (skip discovery).
- Use the branch name above without prompting (skip the "Branch name?" question).
- If the seed has verification.status "degraded", auto-confirm the quality-gate
  override and continue (do not stop for user input).
- After writing the task file, output exactly one line in the format:
    docs created here: docs/tasks/<filename>
  This is the only line from your output that the orchestrator will parse.

All other to-tasks steps run normally.
```

Capture the agent's output. Parse the task file path from the line:
```
docs created here: docs/tasks/<filename>
```

If the line is absent or the file does not exist on disk, stop and report:
> Step 1 failed: to-tasks did not produce a task file path. Check the agent output above.

### Step 2: build-code — execute all tasks and open a PR

Spawn a **fresh** `build-code` agent using the Agent tool:

```
Agent(
  subagent_type="build-code",
  prompt=<see prompt template below>
)
```

**build-code subagent prompt template:**

```
You are running the build-code skill in fully unattended mode.

Task file: <task_file_path>
Run all not_started tasks (do not ask which task ID).

Follow ~/.dotfiles/claude-code-shared/skills/build-code/SKILL.md exactly, with
these overrides for unattended operation:
- Use the task file path above directly (skip the "Which task file?" question).
- Run all not_started tasks (task ID selection: leave blank / run all).
- After the run-complete summary, auto-confirm "Push and open a PR?" — do not
  wait for user input. Run gxpush --pr automatically.
- After gxpush completes, output exactly one line in the format:
    PR URL: <url>
  This is the only line from your output that the orchestrator will parse for
  the PR URL.

All other build-code steps run normally (wave execution, lint/test gates, etc.).
```

Capture the agent's output. Parse the PR URL from the line:
```
PR URL: <url>
```

Also capture the diff at this point:
```bash
git diff main...HEAD
```

If build-code reports any blocker-task failure (halted run), stop and report:
> Step 2 failed: build-code halted due to a blocker task failure. PR not created. Review the build-code output above to re-scope the failing task before re-running.

If the PR URL line is absent, stop and report:
> Step 2 failed: build-code did not output a PR URL. The push may have failed. Review the build-code output above.

### Step 3: pr-code-review — review the diff

Spawn a **fresh** `pr-code-review` agent using the Agent tool:

```
Agent(
  subagent_type="pr-code-review",
  prompt=<see prompt template below>
)
```

**pr-code-review subagent prompt template:**

```
You are running the pr-code-review skill in fully unattended mode.

The PR for this branch is already open at: <pr_url>

Follow ~/.dotfiles/claude-code-shared/skills/pr-code-review/SKILL.md exactly.
Gather the diff via `gh pr diff` using the PR number from the URL above.
Run all five dimension agents in parallel, dedup, run the investigator gate, and
return the full formatted findings.

Do not ask about promoting findings to tasks — output the findings only.
```

Capture the agent's full findings output.

If the pr-code-review agent errors or returns no findings block, stop and report:
> Step 3 failed: pr-code-review did not return findings. Review the agent output above.

### Step 4: Return the summary

Print a consolidated summary to the conversation:

```
sprout-seed complete

Seed:       <seed_path>
Task file:  <task_file_path>
PR:         <pr_url>

── pr-code-review findings ──────────────────────────────────────
<full pr-code-review output>
─────────────────────────────────────────────────────────────────
```

No files are written by the orchestrator beyond what each subagent writes.

## Error handling

If any step fails, stop immediately and report which step failed and why. Do not
attempt the remaining steps. The partial output (task file path, PR URL if
available) is printed before the error so the user can resume manually if needed.

Each step's agent output is printed verbatim in the conversation before the
parsed result, so the user always has the full context when something goes wrong.
