---
name: code-review
description: >
  Comprehensive code review of staged changes or a PR. Checks for bugs, security issues,
  performance, and adherence to project conventions. Use when user says "review my changes",
  "review this PR", "code review", or invokes /review.
model: sonnet
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

## Contract

**Format (optional output):** task file — see `contracts/task-contract.md` (schema_version: `"1"`)
**Role:** conditional producer (produces a task file only when the user promotes findings to tasks)

**HITL vetting required before task output:** After review findings are displayed, present each finding as a numbered checklist. Prompt the user: "Which findings should become tasks? Select by number." Only selected findings are promoted to tasks. Validate the final output:
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  ~/.dotfiles/claude-code-shared/contracts/task-schema.json \
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

## Step 2: Understand context

Before writing a single comment, read the files surrounding each changed section. A line that looks wrong in isolation may be correct in context. Likewise, a line that looks fine may conflict with a neighboring invariant.

Review **every line** — not just the lines that look suspicious. A thorough review catches the things that look fine at a glance.

## Step 3: Evaluate design

Before filing individual findings, assess the change holistically:

- **Design** — Is the overall approach well-designed? Does it fit the existing architecture, or does it introduce an awkward seam?
- **User impact** — Does the functionality actually serve the users of this code (callers, end users, or both)? Are edge cases handled correctly from their perspective?
- **Complexity** — Is the code as simple as it can be for what it does? Flag any unnecessary indirection, over-abstraction, or premature generalization.
- **YAGNI** — Is the developer building things they might need in the future but don't need now? Flag speculative features as 🔵 nit.
- **Parallel safety** — If the code involves concurrency, async operations, or shared mutable state, verify it's safe: no race conditions, no missing awaits, no stale closure captures.
- **Naming** — Are identifiers (variables, functions, types, files) clear and unambiguous? A name that requires a comment to explain is a bad name.
- **Comments** — Comments should explain *why*, not *what*. Flag comments that just restate the code as 🔵 nit. Flag missing "why" comments where the intent is non-obvious as 🟡 risk.

## Step 4: Categorize findings

Group every finding into one of four buckets:

| Label | Meaning |
|-------|---------|
| 🔴 **bug** | Broken behavior, will cause a defect or incident |
| 🟡 **risk** | Works today but fragile — race condition, missing null check, swallowed error, data loss edge case |
| 🔵 **nit** | Style, naming, minor cleanup. Author can ignore without consequence |
| ❓ **q** | Genuine question — you're uncertain whether this is a problem |

A finding with no label is treated as a bug. Don't omit the label.

## Step 4: Format comments

One finding per line. Format: `<file>:L<line>: <label>: <problem>. <fix>.`

**Drop:**
- "I noticed...", "You might want to consider...", "Perhaps..."
- Restating what the code does — the reviewer can read the diff
- Any hedging — if uncertain, use ❓

**Acknowledge good work (required, not optional):**
Genuine praise belongs in the review. If you see a well-designed abstraction, a clever fix, or unusually clean test coverage, call it out explicitly. Keep it brief and specific — one line, tied to a file and line range. Don't manufacture compliments, but don't suppress real ones either. A review with zero positive findings when praiseworthy code is present is an incomplete review.

**Keep:**
- Exact line numbers
- Exact symbol names in backticks
- Concrete fix, not "refactor this"
- The *why* only when the fix isn't obvious

## Tone

A good review asks open-ended questions before making strong statements. Offer alternatives and possible workarounds — don't just point at a problem and demand a fix. Assume you might be missing context and ask for clarification rather than issuing a correction.

Be empathetic. The author spent real time and effort on this change. Be kind and unassuming. Applaud genuinely elegant solutions. A review that only surfaces problems is an incomplete review.

**In practice:**

- Prefer questions: "Could this be null here if the request fails?" over "This will be null and crash."
- Offer alternatives: "One option would be X — not sure if that fits your constraints though."
- Acknowledge effort: if a hard problem was solved cleanly, say so.
- When something looks wrong but might not be: "I might be missing context here — what happens if Y?"
- Reserve strong language (🔴 bug) for things you're confident are broken. Use ❓ liberally.

## Step 5: TypeScript / React checklist

Run through this for every changed file:

- [ ] No `@ts-ignore` or `@ts-expect-error`
- [ ] No unconstrained `any` — prefer `unknown` + type guard
- [ ] No default exports — named exports only
- [ ] No class components — functional only
- [ ] No `==` equality — use `===`
- [ ] No `~~` floor trick — use `Math.floor()`
- [ ] No `+value` coercion — use `Number(value)` or `parseInt`
- [ ] Multi-arg functions that could take a single options object — flag as nit
- [ ] Booleans that represent more than two states — suggest enum

## Step 6: Style / formatting checklist

- [ ] Single quotes, no semicolons, trailing commas, 2-space indent
- [ ] camelCase variables/functions, PascalCase components/types, kebab-case files, SCREAMING_SNAKE_CASE constants
- [ ] No single-letter variable names — including loop counters and `map`/`filter`/`forEach`/`reduce` callback params. Require descriptive names (`i` → `index`, `e` → `event`, `x` → `row`, `acc` is allowed). Flag every occurrence in the changed lines, not just the first.
- [ ] No magic numbers — named constants instead

## Step 7: Design system checklist (frontend only)

- [ ] Spacing uses `theme.space()` — not raw `px`/`rem` numbers
- [ ] Non-spacing lengths use `theme.unit()` — not raw numbers
- [ ] No inline Styled Components — use existing DS primitives or preferably `shadcn`
- [ ] New UI checks `/src/design-system` before inventing a component
- [ ] New domain-aware UI checks `/src/shared-ui` before writing one-off

## Step 8: Testing checklist

- [ ] New behavior has a test
- [ ] Tests use `renderSM` and Testing Library queries (role > text > testId)
- [ ] Network calls use MSW, not internal function stubs

## Step 9: Security checklist

Run this checklist against **every changed file**, not just files that appear security-related.

**Injection & input validation**
- [ ] No user input concatenated into SQL, shell commands, or HTML — use parameterized queries and escaping
- [ ] All external data validated server-side using allowlists, not blocklists
- [ ] Data encoded for its target context (HTML entities for DOM, parameterized for SQL)
- [ ] No `dangerouslySetInnerHTML` without explicit sanitization

**Authentication & session management**
- [ ] Sessions created server-side with strong random identifiers — not derived from user input
- [ ] Sessions fully invalidated on logout — not just cleared client-side
- [ ] No auth state stored in client-controllable locations (localStorage tokens used as sole auth, spoofable headers)

**Access control**
- [ ] Authorization checks happen on every request using server-side session state
- [ ] No reliance on client-supplied roles, flags, or IDs to gate access
- [ ] Sensitive operations don't assume the caller is authorized because they reached the endpoint

**Cryptography**
- [ ] No hardcoded secrets, tokens, or credentials in source
- [ ] No weak algorithms — no MD5, SHA1, or DES for security purposes
- [ ] Key material not logged, exposed in errors, or stored in plaintext

**Error handling**
- [ ] Errors fail closed — deny by default, not allow by default
- [ ] No stack traces, internal paths, or system details in error responses to clients
- [ ] Sensitive data not included in log lines (passwords, tokens, PII)

**Supply chain**
- [ ] New third-party dependencies are from maintained, reputable sources
- [ ] No packages with known CVEs introduced (check via `npm audit` / `yarn audit`)
- [ ] Dependency version ranges are not dangerously wide (e.g. `*` or `>=0.0.0`)

## Provenance

code-review does not write task files. If a future variant writes a task JSON, stamp it with `"producer": "code-review"` and `"source": {"kind": "session", "ref": null}` per `contracts/task-schema.json`.

## Output format

Start with a one-line summary: `N findings: X 🔴 Y 🟡 Z 🔵 W ❓`

Then list findings grouped by file starting with with **FILE :** : <FILE_PATH> and in order of severity. End with a **Verdict**: `Approve` / `Request changes` / `Needs discussion`.

Write nothing that doesn't belong in a comment thread. No preamble, no "Overall this looks great."
