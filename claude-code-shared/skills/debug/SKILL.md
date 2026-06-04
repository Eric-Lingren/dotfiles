---
name: diagnose
description: Disciplined diagnosis loop for hard bugs and performance regressions. Reproduce → minimise → hypothesise → instrument → fix → regression-test. Use when user says "diagnose this" / "debug this", reports a bug, says something is broken/throwing/failing, or describes a performance regression.
model: opus
effort: xhigh
---

<!-- tier-delegate: managed by sync-model-tiers.py -->
## Delegate menial lookups to Haiku (cost control)

During this skill, push pure read-only lookups DOWN to a cheap subagent instead
of running them on the current model. This covers: multi-file grep/glob,
"where is X defined / what calls Y", mapping a directory, reading many files to
locate something, or fetching a URL for reference.

Use the Agent tool with the `caveman:cavecrew-investigator` subagent (Haiku,
returns a compressed file:line answer). If that subagent is unavailable, spawn a
general agent with `model: haiku`. Keep all reasoning, decisions, and edits on
the current model. Delegate only the menial searching.
<!-- /tier-delegate -->

# Diagnose

A discipline for hard bugs. Skip phases only when explicitly justified.

## Contract

**Format (conditional output):** task file — see `contracts/task-contract.md` (schema_version: `"1"`)
**Role:** conditional producer (produces a task file only for non-inline fixes; inline single-file fixes are applied directly)

**Step-0 fires only when a tasks file is actually written:**
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  ~/.dotfiles/claude-code-shared/contracts/task-schema.json \
  <output-path>
```
On non-zero exit: STOP. Report stderr to the user. Do not write the file.

When exploring the codebase, use the project's domain glossary to get a clear mental model of the relevant modules, and check ADRs in the area you're touching.

## Complexity gate

Before entering any phase, assess the bug:

- Is the root cause already visible in the code (typo, wrong constant, obvious off-by-one)?
- Is the fix 1 file, under 10 lines?
- Can you write the failing test and fix in one step?

If all three are true: jump directly to Phase 4 (write tasks). No feedback loop required. State the skip explicitly and explain why.

## Observation log

Maintain a running scratchpad throughout all phases. Format:

```
Tried: <what you did>
Ruled out: <hypothesis or approach, and why>
Pending: <next probe>
```

Update after every significant action. This log feeds Phase 2 hypothesis ranking, the Phase 3 exit summary, and the PR description.

## Phase 1 — Build a feedback loop

**This is the skill.** Everything else is mechanical. If you have a fast, deterministic, agent-runnable pass/fail signal for the bug, you will find the cause — bisection, hypothesis-testing, and instrumentation all just consume that signal. If you don't have one, no amount of staring at code will save you.

Spend disproportionate effort here. **Be aggressive. Be creative. Refuse to give up.**

### Ways to construct one — try them in roughly this order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser check via browser-checker agent** — spawn the `browser-checker` agent (see `agents/browser-checker.md`) with launch context resolved per `~/.dotfiles/claude-code-shared/resources/app-launch-detection.md`. Pass: `base_url`, `url_path`, `assertions` (as falsifiable observable behaviors), `storageState`, Playwright module location, and `run_slug`. Feed the JSON result per `~/.dotfiles/claude-code-shared/resources/browser-check-result.md` directly into the observation log. Re-spawn as the assertion set evolves across hypothesis tests. The agent is stateless — the debug skill owns the retry loop and server lifecycle. CDP MCP (Chrome DevTools) is reserved for live interactive inspection in Phase 3; do not mix it into the browser-checker agent.
5. **Replay a captured trace.** Save a real network request / payload / event log to disk; replay it through the code path in isolation.
6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run 1000 random inputs and look for the failure mode.
8. **Bisection harness.** If the bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so you can `git bisect run` it.
9. **Differential loop.** Run the same input through old-version vs new-version (or two configs) and diff outputs.
10. **HITL loop.** Last resort. If a human must click, drive _them_ with a structured script so the loop is still structured. Captured output feeds back to you.

**Test file requirement.** The feedback loop test must be written to a real test file — not a scratch script, not a REPL session. Record the path. This test becomes `acceptance_criteria[0]` in the Phase 4 task.

### Iterate on the loop itself

Treat the loop as a product. Once you have _a_ loop, ask:

- Can I make it faster? (Cache setup, skip unrelated init, narrow the test scope.)
- Can I make the signal sharper? (Assert on the specific symptom, not "didn't crash".)
- Can I make it more deterministic? (Pin time, seed RNG, isolate filesystem, freeze network.)

A 30-second flaky loop is barely better than no loop. A 2-second deterministic loop is a debugging superpower.

### Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not — keep raising the rate until it's debuggable.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried. Ask the user for: (a) access to whatever environment reproduces it, (b) a captured artifact (HAR file, log dump, core dump, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do **not** proceed to hypothesise without a loop.

### Phase 1 exit gate

Before moving to Phase 2, confirm all of the following:

- [ ] Loop produces the failure mode the **user** described — not a different failure that happens to be nearby. Wrong bug = wrong fix.
- [ ] Failure is reproducible across multiple runs (or, for non-deterministic bugs, at a high enough rate to debug against).
- [ ] Exact symptom captured (error message, wrong output, slow timing) so later phases can verify the fix actually addresses it.
- [ ] Failing test written to a real test file at `<path>` — not a scratch script.

Do not proceed until all four are confirmed.

## Phase 2 — Hypothesise

Generate **3–5 ranked hypotheses** before testing any of them. Single-hypothesis generation anchors on the first plausible idea.

Each hypothesis must be **falsifiable**: state the prediction it makes.

> Format: "If <X> is the cause, then <changing Y> will make the bug disappear / <changing Z> will make it worse."

If you cannot state the prediction, the hypothesis is a vibe — discard or sharpen it.

**Show the ranked list to the user before testing.** They often have domain knowledge that re-ranks instantly ("we just deployed a change to #3"), or know hypotheses they've already ruled out. Wait up to 60 seconds for a response. If no response, proceed with your ranking and note it in the observation log.

## Phase 3 — Instrument

**Capture a test baseline before touching any code.** Run the full test suite. Record:

```
Baseline: <N> passing, <M> failing, <K> skipped
Suite command: <command used>
```

Do not add any instrumentation until this is captured.

Each probe must map to a specific prediction from Phase 2. **Change one variable at a time.**

Tool preference:

1. **Debugger / REPL inspection** if the env supports it. One breakpoint beats ten logs.
2. **Chrome DevTools MCP** — use this for live interactive browser inspection in the main session when an automated repro already exists but live browser state must be observed: network waterfall, memory profile, live console, live DOM inspection. CDP MCP runs in the main session only. Do not use it inside the browser-checker subagent.
3. **Targeted logs** at the boundaries that distinguish hypotheses.
4. Never "log everything and grep".

**Tag every debug log** with a unique prefix, e.g. `[DEBUG-a4f2]`. Cleanup at the end becomes a single grep. Untagged logs survive; tagged logs die.

**Perf branch.** For performance regressions, logs are usually wrong. Instead: establish a baseline measurement (timing harness, `performance.now()`, profiler, query plan), then bisect. Measure first, fix second.

### Phase 3 exit gate

Before moving to Phase 4, complete both steps.

**Step 1: Suite regression check.** Re-run the full test suite. Compare to the baseline captured at Phase 3 entry.

```
Baseline: <N> passing, <M> failing
Current:  <N'> passing, <M'> failing
Delta: <any new failures?>
```

If there are new failures: your instrumentation caused a regression. Fix it before proceeding. Do not move to Phase 4 with a dirty suite.

**Step 2: Root cause summary.** Output this explicitly to the user:

```
Root cause confirmed: <one sentence per bug>
Hypothesis that won: <from Phase 2>
Proposed fix branch: fix/<slug>
```

Do not proceed to Phase 4 until both steps are complete.

## Phase 4 — Write fix tasks, then stop

**The debug skill does not apply any fix. It writes a tasks file and stops. All implementation happens in a separate `/run-tasks` session.**

### Step 1: Branch

Run `git branch --show-current`. Then ask the user:

```
Branching strategy:
1. Single branch for all tasks (you provide the name) — best for a focused fix
2. Per-task branches (auto-generated) — best for independent bugs reviewed separately

Which do you prefer?
```

For most debug sessions a single `fix/<slug>` branch is the right choice. If the user is on `main` or `master`, push strongly toward switching to a fix branch.

If single: ask "Branch name?" and suggest `fix/<slug>` derived from the confirmed root cause. If per-task: derive branch names per the format in branching-strategy.md.

**Wait for user response before continuing.**

See `~/.dotfiles/claude-code-shared/resources/branching-strategy.md` for branch naming rules, derivation format, and JSON recording format.

### Step 2: Write the tasks file

Read the canonical schema now:
```bash
cat ~/.dotfiles/claude-code-shared/contracts/task-schema.json
```
Use that schema exactly. Do not guess field names or structure.

**Multi-bug splitting rule.** If multiple root causes are confirmed:
- Independent bugs (different files, different call paths): write one task per bug.
- Coupled bugs (shared state, same callsite): write one task with compound acceptance criteria, and note the coupling explicitly in the description.

Each task must be self-contained. A future `/run-tasks` session has no memory of this diagnosis. Embed the full context in each task `description` using this pattern:

```
Root cause: <confirmed cause>. Failing scenario: <minimised repro>. Test seam: <file:line — or 'no correct seam: reason'>. Failing test: <path from Phase 1 exit gate>. Fix approach: <what to change and why>.
```

The first acceptance criterion must always be: `"Failing test exists at <path from Phase 1> that reproduces the bug before any fix is applied"`.

**"No testable seam" is a claim, not a default.** Before asserting it, you must attempt to write a test. The following bug types have testable seams even when they appear visual:

- Conditional renders based on auth state or flags → RTL `render()` + `screen.queryBy*` with mocked auth context
- Query `enabled` flags based on user state → mock the hook and assert `enabled` value
- Component receives wrong prop values → RTL render with test user state, assert rendered output

The "no testable seam" exemption is only valid for bugs whose failure mode is a **CSS visual property difference** (e.g. `blur(3px)` vs `background: gray`) that cannot be asserted in a DOM test. Conditional render logic, query gating, and prop threading are always testable.

If a seam genuinely does not exist, set the first acceptance criterion to: `"Visual regression verified manually — no automated test seam exists because <specific reason why DOM testing cannot reach this failure>"`. You must state why, not just that.

If a seam exists but Phase 1 could not build a feedback loop, set the first acceptance criterion to: `"Failing test written at <path> — seam at <file:line>"` using a test you write now.

**Get the next task ID:** Run `~/.dotfiles/claude-code-shared/scripts/next-task-id.sh docs/tasks/`

**Generate the filename:** Run `~/.dotfiles/claude-code-shared/scripts/task-filename.sh debug-<slug>`

Write to `docs/tasks/<filename>`.

For single strategy:
```json
"branching": { "strategy": "single", "branch": "<branch from Step 1>" }
```

For per-task strategy:
```json
"branching": { "strategy": "per-task" }
```
(Each task's `branch` field holds its own auto-derived branch name.)

HITL tasks from debug (rare — e.g. "enable the feature flag to expose the buggy code path") must be hands-only: a keyboard action the AI cannot perform. Never emit a decision-review HITL task.

Set `"producer": "debug"` on the root object. Set `"source": {"kind": "session", "ref": null}`. Follow all field rules from the schema above.

The `follow_ups` array must include one entry for debug cleanup:

```json
{
  "id": "FU-001",
  "title": "Debug cleanup and post-mortem",
  "steps": [
    "Run full test suite and record baseline: <N> passing, <M> failing",
    "Run: grep -r '[DEBUG-' . to find all tagged instrumentation",
    "Remove all [DEBUG-...] tagged instrumentation",
    "Re-run test suite and confirm no new failures vs baseline",
    "Delete any throwaway harness files created during diagnosis",
    "Run: find docs/browser-checks -mindepth 1 -maxdepth 1 -type d | sort -- list all browser-check run dirs",
    "Delete any stale docs/browser-checks run dirs from this debug session: rm -rf docs/browser-checks/<run_dir>",
    "State the winning hypothesis in the PR description",
    "If no correct test seam existed, open /improve-codebase-architecture with the specific coupling details"
  ],
  "trigger_task": "<first task ID>",
  "source": "planned"
}
```

**browser_verify note:** Populate `browser_verify` on each fix task for any bug that manifested as a user-visible UI issue. The URL and assertions come directly from the Phase 1 headless browser feedback loop. Omit `browser_verify` for pure backend or non-UI bugs.

### Step 3: Stop and hand off

After the file is written, output:

```
Tasks written: docs/tasks/<filename>
Tasks: <T-XXXX list>

Next steps:
  /run-tasks docs/tasks/<filename>   — apply fixes with TDD
  /run-task-followups                — walk through FU-001 cleanup after run-tasks completes
  /to-e2e-tasks                      — add e2e coverage (optional)
```

**Phase 4 is complete. Do not open any source file. Do not write any fix code. The debug skill is done.**

## Phase 5 — Cleanup + post-mortem

Run this after `/run-tasks` completes and all tasks are `done`. Triggered by the FU-001 follow-up in the tasks file.

**Run full test suite before cleanup.** Capture:

```
Pre-cleanup: <N> passing, <M> failing
```

Required before declaring done:

- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway prototypes deleted (or moved to a clearly-marked debug location)
- [ ] The winning hypothesis is stated in the PR description so the next debugger learns

**Run full test suite after cleanup.** Compare to pre-cleanup baseline:

```
Post-cleanup: <N'> passing, <M'> failing
Delta: <must be clean — no new failures>
```

If new failures appear: your cleanup caused a regression. Fix before proceeding.

**Then ask: what would have prevented this bug?** If the answer involves architectural change (no correct test seam, tangled callers, hidden coupling), hand off to `/improve-codebase-architecture` with the specifics. Make the recommendation after the fix is in, not before.
