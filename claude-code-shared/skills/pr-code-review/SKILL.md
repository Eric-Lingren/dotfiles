---
name: pr-code-review
description: >
  Comprehensive code review of staged changes or a PR. Checks for bugs, security issues,
  performance, and adherence to project conventions. Use when user says "review my changes",
  "review this PR", "code review", or invokes /review.
model: sonnet
effort: high
invokedBy: human
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

## Contract

**Format (optional output):** task file — see `contracts/task-contract.md` (schema_version: `"1"`)
**Role:** conditional producer (produces a task file only when the user promotes findings to tasks)

**HITL vetting required before task output:** After review findings are displayed, present each finding as a numbered checklist. Prompt the user: "Which findings should become tasks? Select by number." Only selected findings are promoted to tasks. Validate the final output:
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  --instance ~/.dotfiles/claude-code-shared/contracts/task-schema.json \
  <output-path>
```
On non-zero exit: STOP. Report stderr to the user. Do not write the file.

---

You are performing a thorough code review. Follow this process exactly.

## Step 1: Gather the diff

First, identify the current branch and find its associated PR:

```
git branch --show-current
```

If a PR number was explicitly provided, use it directly:
```
gh pr diff <number>
```

Otherwise, look up the PR for the current branch:
```
gh pr view --json number,url 2>/dev/null
```

If a PR exists, fetch its diff:
```
gh pr diff <number>
```

If no PR exists (local-only branch with no upstream PR), fall back to diffing against the merge base with the main branch:
```
git diff $(git merge-base HEAD origin/main)..HEAD
```

Read CLAUDE.md if present — it defines the project's conventions you must enforce.

## Step 1a: Resolve voice profile

Before drafting review comments, resolve this skill's voice profile: look up `pr-code-review` in `claude-code-shared/resources/voice-routing.json`'s `skills` map to get the mapped profile name(s), then resolve each name in the `profiles` map to its `file` path (relative to `claude-code-shared/resources/voice-profiles/`) and read that file. Write review comments in that voice. Do not hardcode a profile filename — always resolve it through `voice-routing.json` at run time.

## Step 1b: Derive accurate line numbers from the diff

**Never cite a line number from the raw diff file's row count.** That number is meaningless to a reader navigating the source file.

Every hunk in a unified diff starts with a header:
```
@@ -old_start,old_count +new_start,new_count @@
```

`new_start` is the first line number in the **new file** for that hunk. Walk each line after the header and maintain a running counter:

- Line starts with ` ` (context): this line exists in the new file at the current counter. Increment counter.
- Line starts with `+` (added): this line exists in the new file at the current counter. **This is the line number to cite for added code.** Increment counter.
- Line starts with `-` (removed): this line does **not** exist in the new file. Do **not** increment counter.
- A new `@@ ... @@` header: reset counter to the new `new_start` value.

When you form a finding, cite the **new-file line number** derived this way, not the diff row.

If the changed line is a removal (a `-` line) with no replacement, cite the nearest surrounding context line in the new file instead, and note it was removed.

## Step 2: Spawn dimension agents in parallel

Spawn all five dimension agents in a **single parallel batch** — one Agent tool call per dimension, all sent in the same message. Do not wait for any agent to finish before launching the next. Pass each agent: (a) the full diff text from Step 1, (b) the CLAUDE.md content if present, and (c) the dimension-specific prompt below.

### Finding format (all dimensions)

Each agent must return findings as a JSON array. Each element:

```json
{
  "file": "path/to/file.ts",
  "line": 42,
  "severity": "bug|risk|nit|q",
  "dimension": "correctness|security|performance|conventions|test-coverage",
  "description": "One-sentence problem statement. One-sentence fix."
}
```

Positive observations (praise) use `severity: "praise"`. Line 0 means file-level.

### Diff-scope rule (all dimensions)

Findings must anchor to a line added or modified in the diff. You may flag a pre-existing issue only if a diff change makes it newly reachable, newly dangerous, or changes its semantics. Do not comment on unchanged code that was already present and unaffected by this PR.

Read surrounding context to understand the change, but the context is for comprehension, not for generating findings.

---

### Dimension: correctness (model: sonnet)

You are performing the correctness dimension of a parallel code review. Return only a JSON array of findings — no prose, no markdown, just the raw array.

Review scope:
- Read the files surrounding each changed section for context. A line that looks wrong in isolation may be correct in context. A line that looks fine may conflict with a neighboring invariant.
- **Design holistically:** overall approach, user impact, complexity (unnecessary indirection/over-abstraction/premature generalization), YAGNI (speculative features → nit), parallel safety (race conditions, missing awaits, stale closures), naming clarity, comment quality (why not what).
- **Fowler code smells:** Mysterious Name, Duplicated Code, Feature Envy, Data Clumps, Primitive Obsession, Repeated Switches, Shotgun Surgery, Divergent Change, Speculative Generality, Message Chains, Middle Man, Refused Bequest. Documented project conventions override the baseline. Each smell is a judgement call — label as "possible X". Most map to nit; raise to risk only when fragile.
- **Severity labels:** `bug` (broken behavior), `risk` (works today but fragile), `nit` (style/naming/minor), `q` (genuine question — unsure if a problem).
- Acknowledge genuinely praiseworthy code with `severity: "praise"`.
- Tone: ask open-ended questions before strong statements; offer alternatives; assume you may be missing context; reserve `bug` for things you are confident are broken.

---

### Dimension: security (model: sonnet)

You are performing the security dimension of a parallel code review. Return only a JSON array of findings — no prose, no markdown, just the raw array.

Review scope — run against **every changed file**:

**Injection & input validation**
- No user input concatenated into SQL, shell commands, or HTML
- All external data validated server-side with allowlists
- Data encoded for target context (HTML entities, parameterized SQL)
- No `dangerouslySetInnerHTML` without explicit sanitization

**Authentication & session management**
- Sessions created server-side with strong random identifiers
- Sessions fully invalidated on logout (not just cleared client-side)
- No auth state in client-controllable locations

**Access control**
- Authorization checks on every request using server-side session state
- No reliance on client-supplied roles/flags/IDs to gate access
- Sensitive operations don't assume caller is authorized just because they reached the endpoint

**Cryptography**
- No hardcoded secrets, tokens, or credentials in source
- No weak algorithms (MD5, SHA1, DES) for security purposes
- Key material not logged, exposed in errors, or stored in plaintext

**Error handling**
- Errors fail closed (deny by default)
- No stack traces/internal paths/system details in client responses
- Sensitive data not in log lines (passwords, tokens, PII)

**Supply chain**
- New third-party dependencies from maintained, reputable sources
- No packages with known CVEs
- Dependency version ranges not dangerously wide (`*` or `>=0.0.0`)

Use severity `bug` for confirmed vulnerabilities, `risk` for likely-exploitable patterns, `nit` for hygiene issues, `q` when uncertain.

---

### Dimension: performance (model: haiku)

You are performing the performance dimension of a parallel code review. Return only a JSON array of findings — no prose, no markdown, just the raw array.

Review scope:
- N+1 query patterns or loops that hit a database/network per iteration
- Missing memoization on expensive pure computations called in render hot paths
- Unnecessary re-renders (unstable references passed as props/deps)
- Large synchronous operations blocking the event loop
- Unbounded data structures (arrays/maps that grow without eviction)
- Missing pagination/streaming on large result sets
- Inefficient data-structure choices (linear scan where a set/map is warranted)

Only flag real performance risks — not micro-optimizations. Use `risk` for patterns that will cause problems at scale, `nit` for minor inefficiencies, `q` when uncertain.

---

### Dimension: conventions (model: haiku)

You are performing the conventions dimension of a parallel code review. Return only a JSON array of findings — no prose, no markdown, just the raw array.

Review scope:

**TypeScript / React**
- No `@ts-ignore` or `@ts-expect-error`
- No unconstrained `any` — prefer `unknown` + type guard
- No default exports — named exports only
- No class components — functional only
- No `==` equality — use `===`
- No `~~` floor trick — use `Math.floor()`
- No `+value` coercion — use `Number(value)` or `parseInt`
- Multi-arg functions that could take a single options object — flag as nit
- Booleans that represent more than two states — suggest enum

**Style / formatting**
- Single quotes, no semicolons, trailing commas, 2-space indent
- camelCase variables/functions, PascalCase components/types, kebab-case files, SCREAMING_SNAKE_CASE constants
- No single-letter variable names (including loop counters and callback params); flag every occurrence
- No magic numbers — named constants instead

**Design system (frontend only)**
- Spacing uses `theme.space()` — not raw `px`/`rem` numbers
- Non-spacing lengths use `theme.unit()` — not raw numbers
- No inline Styled Components — use existing DS primitives or `shadcn`
- New UI checks `/src/design-system` before inventing a component
- New domain-aware UI checks `/src/shared-ui` before writing one-off

All findings here are `nit` unless the violation causes a type error or runtime breakage (then `risk` or `bug`).

---

### Dimension: test-coverage (model: haiku)

You are performing the test-coverage dimension of a parallel code review. Return only a JSON array of findings — no prose, no markdown, just the raw array.

Review scope:
- New behavior has a test
- Tests use `renderSM` and Testing Library queries (role > text > testId)
- Network calls use MSW, not internal function stubs
- Happy path, error path, and edge cases are each covered
- Tests are not testing implementation details (internal function calls, state shape) — they test observable behavior

Use `risk` when new behavior has no test coverage, `nit` for coverage gaps in edge cases, `q` when you are unsure whether a test is needed.

---

## Step 3: Dedup findings

After all five dimension agents return, apply mechanical dedup to their combined JSON arrays:

1. **Group by (file, line).** Findings with the same `file` and `line` values are duplicates regardless of dimension.
2. **Keep max severity.** Severity rank: `bug` > `risk` > `q` > `nit` > `praise`. Retain the highest-ranked severity for the group.
3. **Concatenate descriptions.** If multiple dimensions flagged the same location, join their descriptions with a space. Prefix each description with the dimension name in brackets, e.g. `[correctness] Problem A. Fix A. [security] Problem B. Fix B.` — but only when more than one dimension contributed.
4. **No reconciliation agent.** This is a mechanical merge — no additional agent spawned.

Produce a single flat array of deduped findings. Proceed to the investigator gate with this array.

## Step 4: Pre-submit claim verification (investigator gate)

**This gate is non-optional.** Every finding that contains a factual claim must pass through it before being included in the output or posted as a PR comment. There is no bypass path.

Review findings are factual claims about the code. Before any finding is output or posted, spawn the `investigator` agent using the Agent tool for each factual claim in the finding body. Pass the finding text as the `claim` input along with `cwd` (the repo root) so the investigator can search the codebase.

The investigator is the Opus-tier orchestrator defined in `agents/investigator.md`. It decomposes each claim into sub-claims, routes each to the correct leaf agent (code, web, GitHub, Linear, Notion), and returns a schema-valid `investigation-result` per `contracts/investigation-result-schema.json`.

### Verdict-to-action mapping

The investigator returns one of four verdicts. Apply this gate filter to each finding:

| Verdict | Gate action |
|---------|-------------|
| `VERIFIED_TRUE` | **Proceed** — claim confirmed; include the finding unchanged |
| `CONTESTED` | **Proceed** — genuine expert disagreement; note the contested status in the finding |
| `INSUFFICIENT_EVIDENCE` | **Downgrade** — caveat the claim explicitly; do not state it as fact, or drop the finding if the review comment depends entirely on the unverified claim being true |
| `VERIFIED_FALSE` | **Drop** — exclude this finding from output and from any comment posted to the PR |

**VERIFIED_FALSE — drop the finding:** Remove it from the review output entirely. Do not post it. Annotate your working notes: "dropped: VERIFIED_FALSE".

**INSUFFICIENT_EVIDENCE — downgrade with explicit caveat:** Include the finding only with a hedge (e.g., "I wasn't able to confirm this from the code — could you point me to the specific path?"). Never present an INSUFFICIENT_EVIDENCE claim as an established fact. If the comment cannot be written without asserting the unverified claim, drop it instead.

**VERIFIED_TRUE / CONTESTED — proceed:** These findings proceed to output. VERIFIED_TRUE findings proceed unchanged; CONTESTED findings note the disagreement in the finding body.

### Scope: which findings require the gate

Run the gate on findings that make a verifiable factual assertion about the code (`bug`, `risk`, and any `q` that asserts a specific fact). For each such finding, spawn one investigator call before output.

Pure style/naming `nit` findings that make no factual claim about runtime behavior may skip the gate.

---

## Provenance

pr-code-review does not write task files. If a future variant writes a task JSON, stamp it with `"producer": "pr-code-review"` and `"source": {"type": "session", "ref": null}` per `contracts/task-schema.json`.

## Output format

**Severity-to-emoji mapping** (for rendering deduped findings from the JSON array):

| JSON severity | Display |
|---------------|---------|
| `bug`         | 🔴 **bug** |
| `risk`        | 🟡 **risk** |
| `nit`         | 🔵 **nit** |
| `q`           | ❓ **q** |
| `praise`      | (inline, no count) |

Start with a one-line summary: `N findings: X 🔴 Y 🟡 Z 🔵 W ❓`

Then list findings grouped by file starting with **FILE:** `<FILE_PATH>` and in order of severity. End with a **Verdict**: `Approve` / `Request changes` / `Needs discussion`.

Finding line format: `<file>:L<line>: <label>: <description>`

Write nothing that doesn't belong in a comment thread. No preamble, no "Overall this looks great."

<!-- attribution-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/attribution-capture.md`.
<!-- attribution-capture:end -->

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `pr-code-review`.
<!-- skill-done: pr-code-review -->
<!-- learning-capture:end -->
