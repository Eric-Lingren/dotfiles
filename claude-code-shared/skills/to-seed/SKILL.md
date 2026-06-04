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

### 1. Branch sanity-check (the only interactive prompt)

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

This is the **only** interactive prompt before the pipeline gate. Do not ask about content, theme, output directory, or anything else.

### 2. Synthesize the seed JSON

Read the full conversation. Distill it into the shape defined in `contracts/seed-schema.json` in the dotfiles repo. Read the schema for field definitions, types, and required/optional classification. Required fields are always present. Optional fields are omitted when the conversation contains no relevant content.

**Synthesis rules:**
- Never fabricate content. Only include what the conversation explicitly contains or implies.
- Do not invent `user_stories` or `success_metrics` to fill optional limbs when the conversation is not feature-scoped.
- `decisions` must be concrete resolved statements, not restatements of the conversation. Every decision someone reached belongs here.
- `open_threads` holds **genuine unresolved JUDGMENT only** — questions where the answer changes what gets built and no consensus was reached. It must be empty when everything is decided.
- **Decided-but-conditional implementation details are NOT open threads.** If something was decided (e.g. "use Registry API if jsonschema >=4.18, else RefResolver"), it is a decided implementation detail. Put it in `implementation_decisions` or in a task's acceptance criteria. Do NOT file it as an open thread just because it has a conditional.
- `next_action` is singular — the most important next step, not a list.

**Thread classification (required before writing):**

Before writing the seed, route every thread from the conversation through exactly one of three gates:

1. **RESOLVE → `decisions[]`**: A judgment was reached during this session. Write it as a concrete resolved statement.
2. **DEFER → `deferred[]`**: Real work that is consciously set aside for a later effort. Write it as `{text, rationale, context, source_seed}` with enough context to resume independently.
3. **REJECT → `out_of_scope[]`**: Explicitly excluded from scope. Write it as `{text, rationale}` so to-tasks can use rationale as a negative guard.

Nothing stays undecided. If a thread truly cannot be resolved, it must exit via DEFER (if worth doing later) or REJECT (if not). The only exception: a genuinely open judgment that the user explicitly says needs another grill session belongs in `open_threads`.

**Status derivation (required):**

After routing all threads, derive `status`:
- `"ready"` if `open_threads` is empty (all judgments resolved).
- `"draft"` if `open_threads` is non-empty (genuine unresolved judgment remains).

**Provenance fields (Mode 1):**

Set `producer: "to-seed"`. Set `source: {"kind": "session", "ref": null}` for fresh seeds generated from a conversation.

### 2b. Merge a base seed (Mode 2 only)

Run this step only when a handoff path was passed in ARGUMENTS. Skip it entirely in Mode 1.

1. Read the handoff doc at the given path.
2. Find the machine-readable seed-context block inside it (a fenced ```json block under a `## Seed Context` heading). Parse out `base_seed` (the path to the original seed file).
3. Read the base seed JSON. This is the merge foundation — it carries every decision and field from the original session, so nothing from that conversation is lost.
4. Synthesize the current grill conversation's resolutions, then merge onto the base seed:
   - Apply thread classification (step 2 above) to ALL threads — from both the handoff and the current conversation.
   - Move every now-resolved thread from `open_threads` into `decisions` as a concrete resolved statement.
   - Route deferred items to `deferred[]` and rejected items to `out_of_scope[]`.
   - Leave any still-unresolved threads in `open_threads`.
   - Append any genuinely new decisions surfaced during the grill.
   - Update `summary` and `next_action` to reflect the merged state.
   - Derive `status` as defined in step 2.
5. Set `producer: "to-seed"`. Set `source: {"kind": "seed", "ref": "<base-seed-path>"}` where `<base-seed-path>` is the path of the original seed from the handoff. **Do NOT write a `base_seed` field** — lineage is expressed entirely through `source`.
6. The merged object is what gets written in step 3. It is a new seed file, not an in-place overwrite of the base.

### 3. Write the seed file

1. Derive a slug from the title (lowercase, kebab-case, max ~40 chars).
2. Run `~/.dotfiles/claude-code-shared/scripts/doc-filename.sh <slug> json` to get the filename (`YYYYMMDD-HHMM-<slug>.json`).
3. Resolve the output path: `docs/seeds/<filename>`. Create `docs/seeds/` if it does not exist.
4. Write the JSON file with all required fields including `schema_version: "3"`, `producer`, `source`, and `status`. Never auto-commit.

### 4. Pipeline gate

After writing, check `status`:

**If `status` is `"draft"` (open_threads non-empty):**

The seed is not ready. to-tasks hard-refuses a draft seed, so finishing here would block the pipeline. Refuse to show the fan-out and instead:

1. Generate a handoff doc (same logic as `/handoff`). Save it under `docs/handoffs/` using `~/.dotfiles/claude-code-shared/scripts/doc-filename.sh <slug> md`.
2. Frame the open threads as the explicit agenda for the next session.
3. Name `grill-me` in the handoff's "suggested skills" section.
4. Embed a machine-readable seed-context block so the Mode 2 return trip can find the base seed:

   ````
   ## Seed Context
   ```json
   {
     "base_seed": "docs/seeds/<filename>",
     "open_threads": ["<thread 1>", "<thread 2>"]
   }
   ```
   ````

5. Output to the user:

   ```
   Draft seed written to docs/seeds/<filename>
   Open threads: <N> (listed above)

   This seed cannot proceed until all judgment threads are resolved.
   Handoff written to docs/handoffs/<handoff-filename>

   To resolve: open a fresh window and run /grill-me <handoff-path>
   When done, run /to-seed <handoff-path> to merge resolutions back.
   ```

6. **Stop. Do not show the fan-out menu. Do not invoke any downstream skill.**

**If `status` is `"ready"` (open_threads empty):**

Show the fan-out using `AskUserQuestion`:

```
Seed written to docs/seeds/<filename> (status: ready)

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

**CRITICAL:** Never commit any artifact. Never push. The only things written to disk are the seed file (every run) and, when status is draft, the handoff doc.
