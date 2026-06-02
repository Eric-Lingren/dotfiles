# Handoff: Context-Loader Agent Grill Session

**Date:** 2026-06-02
**Purpose:** Grill session to define the `context-loader` agent and determine what tasks its implementation should produce.

---

## Background

`/improve-skill to-prd-html` completed this session. Final scores:

- Behavioral: **96/100** (2 iterations, exit: strong_score)
- Structural: **86/100** (6/7 pass; only failure is token weight driven by runtime assets)
- Architecture: **88/100** (7/8 signals pass)

The one confirmed architecture finding (A6) is the entry point for this grill session.

Eval artifacts live at:
`~/.dotfiles/claude-code-shared/skills/improve-skill/runs/to-prd-html/`

---

## The A6 Finding (Architecture, NEW)

**Signal:** A6 — Extractable pattern present in 2+ skills.

**Finding:** The inline repo exploration pattern — read `CONTEXT.md` if it exists, scan `docs/adr/` for domain decisions, extract and apply domain vocabulary — is re-implemented independently in **5 skills**:

| Skill | Location |
|---|---|
| `to-prd-html` | SKILL.md line 12 |
| `to-tasks` | SKILL.md lines 26-28 |
| `improve-codebase-architecture` | SKILL.md line 49+ |
| `improve-component` | SKILL.md lines 191-192 |
| `to-e2e-tests` | SKILL.md lines 96, 129 |

Each skill instructs the session model to do the read inline. None delegate to a subagent.

**Proposed solution:** A shared `context-loader` agent that reads `CONTEXT.md` and `docs/adr/`, distills domain vocabulary and key ADR constraints into a compact JSON payload, and returns it to the caller. All five skills spawn this agent instead of reading inline.

---

## Open Questions for Grill Session

The grill session should stress-test the design and surface the concrete task boundaries. Key questions to resolve:

1. **Output contract:** What JSON shape does `context-loader` return? Vocabulary terms only? ADR decisions? Both? What fields are required vs optional?

2. **Scope boundaries:** Does the agent read only `CONTEXT.md` + `docs/adr/`, or does it also scan other common vocab sources (e.g. `README.md`, `docs/`, package names)?

3. **Fallback behavior:** When `CONTEXT.md` and `docs/adr/` both missing, does the agent return an empty payload, an error, or infer from other signals?

4. **Registration:** Does this agent live in `~/.dotfiles/claude-code-shared/agents/` and get registered in `registry.json`? What is its agent type name?

5. **Consumer update scope:** Do all 5 skills get updated in one PR, or does each skill get its own PR? Is there a migration order?

6. **Agent type:** Is this a new `subagent_type` entry, or does it reuse an existing agent type (e.g. `Explore`)?

7. **Token impact:** The A6 pattern fires on every invocation of those 5 skills. Does delegating to an agent increase or decrease net token cost vs inline reads?

8. **Testing:** How do we eval that `context-loader` returns correct output? Does it get its own eval.json in `improve-skill/runs/`?

---

## What the Grill Session Should Produce

After grilling, the output should be a clear set of tasks (suitable for `/to-tasks`) covering:

- The `context-loader` agent definition (`agents/context-loader/SKILL.md` or similar)
- Output schema definition
- Updates to each of the 5 consumer skills
- Registry entry in `registry.json`
- Eval scaffold for the new agent (optional, but ideal)

---

## Suggested Skills

| Skill | Purpose |
|---|---|
| `/grill-me` | Stress-test the `context-loader` design before committing to tasks |
| `/grill-with-docs` | Grill against the existing skill directory conventions and registry schema |
| `/to-tasks` | Convert the grilled design into a JSON task file for implementation |
| `/register-skill` | Register the new agent once built |
| `/improve-skill context-loader` | Eval the agent after it is built |

---

## Relevant Paths

```
~/.dotfiles/claude-code-shared/skills/          # all skill SKILL.md files
~/.dotfiles/claude-code-shared/agents/          # agent definitions + registry.json
~/.dotfiles/claude-code-shared/resources/skill-directory-conventions.md
~/.dotfiles/claude-code-shared/skills/improve-skill/runs/to-prd-html/scores.json
~/.dotfiles/claude-code-shared/skills/to-prd-html/SKILL.md
~/.dotfiles/claude-code-shared/skills/to-tasks/SKILL.md
~/.dotfiles/claude-code-shared/skills/improve-codebase-architecture/SKILL.md
~/.dotfiles/claude-code-shared/skills/improve-component/SKILL.md
~/.dotfiles/claude-code-shared/skills/to-e2e-tests/SKILL.md
```
