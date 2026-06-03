---
name: to-seed
description: Distill the current conversation or grill session into a standardized JSON IR (seed) and save it to docs/seeds/. Use when user wants to capture decisions and context from a conversation before moving to /to-prd-html, /to-tasks, or /prototype.
model: sonnet
effort: xhigh
---

# To Seed

Distill the current conversation into a structured JSON seed file. Works standalone from any conversation — not grill-only. No content-forking prompts, no theme prompts, no dir-confirm, no context-loader.

## Process

### 1. Branch sanity-check (the only prompt)

Run `git rev-parse --abbrev-ref HEAD` to get the current branch. Then ask ONE question using `AskUserQuestion`:

```
Where should this seed go?
1. Current branch: <branch-name>
2. Switch to an existing branch
3. Create a new branch (feat / fix / spike)
```

- **Option 1**: continue on the current branch.
- **Option 2**: ask "Branch name?" — run `git switch <name>`. If the switch fails (dirty working tree), tell the user to commit or stash first and stop.
- **Option 3**: propose `feat/<slug>`, `fix/<slug>`, or `spike/<slug>` derived from the conversation topic. Let the user accept or type a custom name. Run `git switch -c <branch-name>`. If the switch fails, stop and tell the user.

This is the **only** prompt. Do not ask about content, theme, output directory, or anything else.

### 2. Synthesize the seed JSON

Read the full conversation. Distill it into the shape defined in `resources/seed-example.json` in this skill's directory. Read that file before writing. Use it as the canonical field reference and output template. All core spine fields are required; feature limbs are optional — only include them when the conversation contains relevant content.

**Core spine (always required):**

| Field | Type | Description |
|---|---|---|
| `schema_version` | string | Always `"2"` |
| `source` | string | Always `"to-seed"` |
| `title` | string | Short human-readable title for this topic |
| `slug` | string | Kebab-case, max ~40 chars, derived from title |
| `created` | string | ISO 8601 timestamp (now) |
| `summary` | string | One paragraph: what was discussed and what was decided |
| `decisions` | array of strings | Resolved decisions. Each entry is a plain-text statement. |
| `open_threads` | array of strings | Unresolved questions that need follow-up. Empty array if none. |
| `next_action` | string | The single most important next step |

**Feature limbs (optional — omit entirely if no relevant content exists):**

- `problem_statement` — the problem in plain text
- `solution` — the solution in plain text
- `evidence` — one or two sentences: data, complaints, or research that motivated this
- `success_metrics` — array of specific measurable strings
- `user_stories` — array of `{actor, feature, benefit}` objects (minimum 5 if included)
- `implementation_decisions` — array of plain-text strings (modules, interfaces, schema, APIs)
- `testing_decisions` — array of plain-text strings
- `out_of_scope` — array of plain-text strings
- `risks_and_tradeoffs` — array of plain-text strings
- `further_notes` — array of plain-text strings

**Synthesis rules:**
- Never fabricate content. Only include what the conversation explicitly contains or implies.
- Do not invent `user_stories` or `success_metrics` to fill optional limbs when the conversation is not feature-scoped.
- `decisions` must be concrete resolved statements, not restatements of the conversation. Every decision someone reached belongs here.
- `open_threads` must be genuinely unresolved questions — do not include things that were decided.
- `next_action` is singular — the most important next step, not a list.

### 3. Write the seed file

1. Derive a slug from the title (lowercase, kebab-case, max ~40 chars).
2. Run `~/.dotfiles/claude-code-shared/scripts/doc-filename.sh <slug> json` to get the filename (`YYYYMMDD-HHMM-<slug>.json`).
3. Resolve the output path: `docs/seeds/<filename>`. Create `docs/seeds/` if it does not exist.
4. Write the JSON file. Never auto-commit.

### 4. Fan-out menu

After writing, present a fan-out using `AskUserQuestion`:

```
Seed written to docs/seeds/<filename>

What next?
1. /to-prd-html <seed-path> — render a full HTML PRD from this seed
2. /to-tasks <seed-path> — break this into tasks for /run-tasks
3. /prototype — explore ideas or UI options before committing
4. Nothing yet
```

- If the user picks **1**: invoke `/to-prd-html` with the seed path as argument.
- If the user picks **2**: invoke `/to-tasks` with the seed path as argument.
- If the user picks **3**: invoke `/prototype`.
- If the user picks **4**: do nothing. Confirm the seed path and stop.

**CRITICAL:** Never commit any artifact. Never push. The seed file is the only thing written to disk.
