---
name: to-seed
description: Distill the current conversation or grill session into a standardized JSON IR (seed) and save it to docs/seeds/. Use when user wants to capture decisions and context from a conversation before moving to /to-prd-html, /to-tasks, or /prototype.
argument-hint: "[optional: path to a handoff doc that carries a base seed to merge into]"
model: sonnet
effort: xhigh
---

# To Seed

Distill the current conversation into a structured JSON seed file. Works standalone from any conversation — not grill-only. No content-forking prompts, no theme prompts, no dir-confirm, no context-loader.

## Input modes

to-seed has two ingest modes. Detect which one applies before doing anything else.

- **Mode 1 — conversation (default):** No handoff path was passed in ARGUMENTS. Synthesize a fresh seed from the live conversation (standalone or a grill session). This is the common case.
- **Mode 2 — handoff merge:** A handoff doc path was passed in ARGUMENTS. This is the return trip after open threads were resolved in a separate grill session. Read the handoff, parse the embedded base seed path out of it, load that base seed as the merge foundation, then fold the current conversation's resolutions on top. See step 2b.

Mode 2 is additive: it reads the handoff AND the current conversation, then merges both onto the base seed. The handoff is the only artifact the user carries — the base seed path lives inside it, so the user never passes a seed path directly.

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

Read the full conversation. Distill it into the shape defined in `resources/seed-example.json`. Read the `_schema` block for field definitions, types, and required/optional classification. Required fields are always present. Optional fields are omitted when the conversation contains no relevant content.

**Synthesis rules:**
- Never fabricate content. Only include what the conversation explicitly contains or implies.
- Do not invent `user_stories` or `success_metrics` to fill optional limbs when the conversation is not feature-scoped.
- `decisions` must be concrete resolved statements, not restatements of the conversation. Every decision someone reached belongs here.
- `open_threads` must be genuinely unresolved questions — do not include things that were decided.
- `next_action` is singular — the most important next step, not a list.

### 2b. Merge a base seed (Mode 2 only)

Run this step only when a handoff path was passed in ARGUMENTS. Skip it entirely in Mode 1.

1. Read the handoff doc at the given path.
2. Find the machine-readable seed-context block inside it (a fenced ```json block under a `## Seed Context` heading). Parse out `base_seed` (the path to the original seed file).
3. Read the base seed JSON. This is the merge foundation — it carries every decision and field from the original session, so nothing from that conversation is lost.
4. Synthesize the current grill conversation's resolutions, then merge onto the base seed:
   - Move every now-resolved thread from `open_threads` into `decisions` as a concrete resolved statement.
   - Leave any still-unresolved threads in `open_threads`.
   - Append any genuinely new decisions surfaced during the grill.
   - Update `summary` and `next_action` to reflect the merged state.
   - Set the optional `base_seed` field on the output to the original seed path (lineage/provenance).
5. The merged object is what gets written in step 3. It is a new seed file, not an in-place overwrite of the base.

### 3. Write the seed file

1. Derive a slug from the title (lowercase, kebab-case, max ~40 chars).
2. Run `~/.dotfiles/claude-code-shared/scripts/doc-filename.sh <slug> json` to get the filename (`YYYYMMDD-HHMM-<slug>.json`).
3. Resolve the output path: `docs/seeds/<filename>`. Create `docs/seeds/` if it does not exist.
4. Write the JSON file. Never auto-commit.

### 4. Fan-out menu

After writing, present a fan-out using `AskUserQuestion`. The fifth option appears **only when `open_threads` is non-empty**.

```
Seed written to docs/seeds/<filename>

What next?
1. /to-prd-html <seed-path> — render a full HTML PRD from this seed
2. /to-tasks <seed-path> — break this into tasks for /run-tasks
3. /prototype — explore ideas or UI options before committing
4. Nothing yet
5. Resolve open threads now — generate a handoff for a fresh grill session   (only if open_threads is non-empty)
```

- If the user picks **1**: invoke `/to-prd-html` with the seed path as argument.
- If the user picks **2**: invoke `/to-tasks` with the seed path as argument.
- If the user picks **3**: invoke `/prototype`.
- If the user picks **4**: do nothing. Confirm the seed path and stop.
- If the user picks **5**: generate the resolution handoff (step 5 below).

`open_threads` is honest data — it is always written to the seed and rendered downstream. There is no gate. The fifth option is a non-blocking offer, not a wall.

### 5. Generate the resolution handoff (option 5 only)

Triggered only when the user picks option 5. The goal is a single artifact the user can carry into a fresh window — it holds everything needed to resume, so the user never juggles a seed path by hand.

1. Generate a handoff doc for the current conversation (same logic as `/handoff`). Save it under `docs/handoffs/` using `~/.dotfiles/claude-code-shared/scripts/doc-filename.sh <slug> md`.
2. Frame the open threads as the explicit agenda for the next session.
3. Name `grill-me` in the handoff's "suggested skills" section.
4. Embed a machine-readable seed-context block so a Mode 2 return trip can find the base seed without the user pasting a path:

   ````
   ## Seed Context
   ```json
   {
     "base_seed": "docs/seeds/<filename>",
     "open_threads": ["<thread 1>", "<thread 2>"]
   }
   ```
   ````

5. Output the handoff file path to the user, then tell them: open a fresh window and run `/grill-me <handoff-path>` to resolve the threads. When done, run `/to-seed <handoff-path>` to merge the resolutions back (Mode 2).

**CRITICAL:** Never commit any artifact. Never push. The only things written to disk are the seed file (every run) and, when option 5 is chosen, the handoff doc.
