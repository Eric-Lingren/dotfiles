---
name: code-currency-checker
description: "PLACEHOLDER — NOT YET IMPLEMENTED. Future inline agent for verifying code currency: checks whether libraries, frameworks, and patterns in a document or codebase are current vs. outdated. Spawned by host skills (to-prd-html, to-tasks, run-tasks) at the END of their runs to append a currency summary. NOT a factual truth checker — use the fact-checker agent for that."
tools: WebSearch, WebFetch, Bash, Read
model: sonnet
---

> **PLACEHOLDER — NOT YET IMPLEMENTED**
>
> This agent stub reserves the name and records design intent from the grill session.
> A dedicated `/grill-me` session is required before this agent can be built.
> See FU-001 in `docs/tasks/20260601-1524-fact-check-skill-rebuild.json`.

---

## Design intent (from grill session 2026-06-01)

### What this agent checks

Code CURRENCY — not factual truth. Examples:
- "Are we using the latest stable TanStack Query version?"
- "Are these Django patterns current best practice, or from an older major version?"
- "Is this React pattern (class components, legacy context) still recommended?"
- "Is this package deprecated or unmaintained?"

This is distinct from the `fact-checker` agent, which checks factual/anecdotal claims.

### Source strategy

1. **Context7 MCP docs first** — authoritative, version-aware library documentation.
2. **Web search second** — for packages without Context7 coverage or for deprecation notices.
3. Never raw web search only. Context7 is the primary source for code currency questions.

### Verdict semantics

Not true-vs-false. Current-vs-outdated:
- **CURRENT** — using the latest stable version and recommended patterns
- **MINOR_DRIFT** — mostly current, a newer version or pattern is available but not breaking
- **OUTDATED** — a significant version behind, deprecated pattern, or better alternative exists
- **DEPRECATED** — the package/API/pattern is officially deprecated or abandoned
- **UNVERIFIABLE** — could not confirm currency from available sources

### Invocation model

- **Not a manual slash skill.** Spawned by host skills (to-prd-html, to-tasks, run-tasks) at the END of their execution.
- Appends a currency summary to the host skill's output — does NOT pause mid-workflow.
- Findings are advisory/flag-only. Never blocks the host skill.

### Open design questions (to resolve in grill session)

- Exact claim extraction for code/version claims (different from the factual regex pre-pass)
- Context7 MCP tool invocation pattern within an agent context
- Current-vs-outdated verdict thresholds (what counts as "too old"?)
- Specific list of host skills that will spawn this agent
- Whether a thin slash skill (/fact-check-currency) is needed for manual invocation
