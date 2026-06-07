---
name: to-seed
description: Distill the current conversation or grill session into a standardized JSON IR (seed) and save it to docs/seeds/. Use when user wants to capture decisions and context from a conversation before moving to /to-prd-html, /to-tasks, or /prototype.
argument-hint: "[optional: path to a handoff doc that carries a base seed to merge into]"
model: sonnet
effort: high
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

**gxcheck pre-flight:** Before asking the user, run `~/.dotfiles/.scripts/gxcheck` and surface its output as a brief status block (e.g. `Branch check: OK: branch looks clean`). This is advisory only — the skill continues regardless of the output.

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
- `open_threads` holds **genuine unresolved JUDGMENT only** — questions where the answer changes what gets built and no consensus was reached. It must be empty when everything is decided. Each entry is an object `{id, text, first_seen_iteration}`. Assign a stable id (e.g. `ot-001`, `ot-002`) that never changes, even after disposal.
- `disposed_threads` is the lock list of threads that were disposed during this or any prior session. Each entry is `{id, text, disposition, iteration}` where disposition is `decided`, `deferred`, or `rejected`. This list is immutable once written — entries are never removed.
- `iteration` is an integer tracking how many grill/verification cycles this seed has gone through. Start at 1 for fresh seeds.
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

**Disposed-id lock list (required before verification):**

After routing all threads, extract the ids from `disposed_threads`. This is the lock list. It is minted here, before any adversary agent spawns, so agents cannot re-raise a disposed thread under any name.

**Provenance fields (Mode 1):**

Set `producer: "to-seed"`. Set `source: {"type": "session", "ref": null}` for fresh seeds generated from a conversation.

### 2b. Merge a base seed (Mode 2 only)

Run this step only when a handoff path was passed in ARGUMENTS. Skip it entirely in Mode 1.

1. Route the handoff path through resolve-ref.sh before reading (see `resources/resolve-ref-pattern.md`): Run `bash ~/.dotfiles/claude-code-shared/scripts/resolve-ref.sh $(basename <handoff-path>)`. On archive hit (output starts with `ARCHIVE:`), use the extracted content. On not-found (exit non-zero), surface the diagnostic and ask "Continue anyway?" — bypass rebuilds context from conversation.
2. Read the handoff doc (active path or archive content from step 1).
3. Find the machine-readable seed-context block inside it (a fenced ```json block under a `## Seed Context` heading). Parse out `base_seed` (the path to the original seed file).
3. Read the base seed JSON. This is the merge foundation — it carries every decision and field from the original session, so nothing from that conversation is lost.
4. Synthesize the current grill conversation's resolutions, then merge onto the base seed:
   - Apply thread classification (step 2 above) to ALL threads — from both the handoff and the current conversation.
   - Move every now-resolved thread from `open_threads` into `decisions` as a concrete resolved statement.
   - Route deferred items to `deferred[]` and rejected items to `out_of_scope[]`.
   - Leave any still-unresolved threads in `open_threads`.
   - Append any genuinely new decisions surfaced during the grill.
   - Update `summary` and `next_action` to reflect the merged state.
   - Derive `status` as defined in step 2.
5. Set `producer: "to-seed"`. Set `source: {"type": "seed", "ref": "<base-seed-path>"}` where `<base-seed-path>` is the path of the original seed from the handoff. **Do NOT write a `base_seed` field** — lineage is expressed entirely through `source`.
6. The merged object is what gets written in step 3. It is a new seed file, not an in-place overwrite of the base.

### 3. Verification stage

Run this stage after synthesis populates all seed fields in memory and before anything is written to disk.

**Pipeline order is strict:** synthesis mints the disposed-id lock list (step 2) before any persona agent spawns. This ensures agents cannot re-raise a disposed thread by any name.

#### 3a. Prepare the cleaned transcript and seed temp file

Before spawning any persona, produce two temp files:

**Cleaned transcript:**

1. Resolve the session JSONL path using `$CLAUDE_CODE_SESSION_ID` and `$CLAUDE_CONFIG_DIR` (or the hook-provided `transcript_path` env var). The filter script handles resolution — see `~/.dotfiles/claude-code-shared/scripts/filter-session-transcript.sh --help`.

2. Run:
   ```bash
   bash ~/.dotfiles/claude-code-shared/scripts/filter-session-transcript.sh /tmp/cleaned-transcript-${CLAUDE_CODE_SESSION_ID}.jsonl
   ```
   Store the output path as `CLEANED_TRANSCRIPT_PATH`.

3. If the script exits non-zero (JSONL not found or unresolvable), mark the entire verification stage as failed (all 4 personas failed), note the error, and jump to step 3d. Do not spawn any persona agents. Do not author or summarize the transcript as a substitute.

**The orchestrator must never author or summarize the transcript.** Only the deterministic pre-filter script may produce `CLEANED_TRANSCRIPT_PATH`. An LLM-authored transcript reintroduces the mirror problem this stage is designed to prevent.

**Seed temp file:**

Write the draft seed JSON to:
```
/tmp/seed-${CLAUDE_CODE_SESSION_ID}.json
```
Store the output path as `SEED_PATH`. Pass this path to all personas and judges. Do not inline the seed JSON in any agent prompt — passing a file path prevents generation drift when spawning multiple agents simultaneously.

#### 3b. Spawn all 4 adversary persona agents in parallel

In a single message, spawn all four adversary personas simultaneously. Each persona receives (per `~/.dotfiles/claude-code-shared/contracts/persona-input-contract.md`):
- `seed_path: <SEED_PATH>` — a file path, not inline JSON
- `transcript_path: <CLEANED_TRANSCRIPT_PATH>` — a file path, not inline transcript text
- The disposed-id lock list (hard constraint: do not raise threads with these ids)

Agents to spawn (by registered agent name, not file path):
- `personas:persona-grounding` — hunts unsupported content and fabricated rationale
- `personas:persona-accuracy` — hunts semantic drift and stale-resolution
- `personas:persona-completeness` — hunts missed branches, premature closure, dropped dependencies, merge-loss
- `personas:persona-coherence` — hunts contradiction, misclassification, dropped human dispositions, relabel-resurrection

Each persona returns a JSON array of refutation objects (`[]` if nothing found). Validate each returned result against the shape defined in `~/.dotfiles/claude-code-shared/contracts/refutation-contract.md`. On a parse mismatch or non-JSON response, retry that persona once. If the retry also fails, note the failure (agent name + error) and continue to 3c.

**Adversarial framing:** the panel's job is to disprove, not to improve. Additions and new open_threads the panel surfaces auto-apply. Removals (claiming a decision is wrong and should be removed) require a cited transcript span as evidence — no span, no removal.

#### 3c. Short-circuit or adjudicate

**If all four personas return empty arrays (`[]`):** skip the judge stage entirely. There are no refutations to adjudicate. Proceed directly to step 3d with `refutations_upheld: 0` and `refutations_screened: 0`.

**Otherwise:** maintain a `refutations_screened` counter (starts at 0). For each refutation returned by any persona, apply the two-round escalation ladder:

**Round 1 — screener:** spawn 1 `personas:persona-judge` instance using the Sonnet model. The judge receives (per `~/.dotfiles/claude-code-shared/contracts/persona-input-contract.md`): the single refutation object, `seed_path: <SEED_PATH>`, and `transcript_path: <CLEANED_TRANSCRIPT_PATH>`. Validate the returned result against `~/.dotfiles/claude-code-shared/contracts/verdict-contract.md`. On a parse mismatch or non-JSON response, retry that judge once.

- **Round-1 returns `rejected`:** increment `refutations_screened`. Move to the next refutation. Do not escalate.
- **Round-1 returns `upheld`:** escalate to round 2.
- **Round-1 judge fails after retry:** record the failure (same degraded-path accounting as 3b) and skip the refutation.

**Round 2 — panel:** spawn 3 fresh `personas:persona-judge` instances simultaneously, each using the Sonnet model. The round-1 verdict is not reused as a pre-vote — all 3 instances receive the refutation fresh. Validate each returned result against `~/.dotfiles/claude-code-shared/contracts/verdict-contract.md`. On a parse mismatch or non-JSON response, retry that judge instance once. Collect non-failed verdicts. Apply a 2-of-3 majority — if fewer than 2 non-failed verdicts are available, fall through to the failure handler below. If the refutation is upheld: apply it to the draft seed in memory (see adversarial framing above).

**Failure handling (round-2 judges):** if 2 or more judge instances fail for the same refutation, skip that refutation, record the failure, and continue.

#### 3d. Build the verification stamp and clean up

After all refutations are adjudicated:

1. Delete both temp files:
   ```bash
   rm -f "${CLEANED_TRANSCRIPT_PATH}" "${SEED_PATH}"
   ```

2. Write the `verification` field onto the draft seed:

```json
{
  "iteration": <current iteration integer>,
  "personas": ["grounding", "accuracy", "completeness", "coherence"],
  "refutations_upheld": <count of upheld refutations>,
  "refutations_screened": <count of refutations terminated at round-1 via lone reject>,
  "clean": <true if refutations_upheld === 0>,
  "status": "verified"
}
```

**Degraded path:** if any persona or judge failure was recorded in 3b/3c and was not recovered, set `verification.status` to `"degraded"` instead of `"verified"`. Do not silently write a degraded seed. Present the user with:

```
Verification incomplete — the following agents failed to complete:
  <list of failed agent names and errors>

Options:
1. Rerun only the agents that failed
2. Save as-is — write the seed with verification.status: 'degraded'
   (note: to-tasks will surface this with an override prompt — you will not be hard-blocked)
```

Abort is never an option. The seed is always written. If the user picks option 2, write `verification.status: "degraded"` and continue to step 4.

### 4. Write the seed file

1. Derive a slug from the title (lowercase, kebab-case, max ~40 chars).
2. Run `~/.dotfiles/claude-code-shared/scripts/doc-filename.sh <slug> json` to get the filename (`YYYYMMDD-HHMM-<slug>.json`).
3. Resolve the output path: `docs/seeds/<filename>`. Create `docs/seeds/` if it does not exist.
4. Write the JSON file with all required fields including `schema_version: "4"`, `producer`, `source`, `status`, and `verification`. Never auto-commit.

### 5. Pipeline gate

After writing, check `status`:

**If `status` is `"draft"` (open_threads non-empty):**

Print the open threads and suggest how to continue. Do not use `AskUserQuestion`. Output text like:

```
Seed written to docs/seeds/<filename> (status: draft)
Open threads (<N>):
  - <thread text>
  ...

To resolve:
  /grill-me docs/seeds/<filename> — drill these threads in this window
  /grill-with-docs docs/seeds/<filename> — drill against the existing domain model
  Say "write a handoff" to park this for a fresh window.
```

Then stop. If the user responds "write a handoff" (or similar), write the handoff doc:
  1. Generate a handoff doc (same logic as `/handoff`). Save it under `docs/handoffs/` using `~/.dotfiles/claude-code-shared/scripts/doc-filename.sh <slug> md`.
  2. Frame the open threads as the explicit agenda for the next session.
  3. Name `grill-me` and `grill-with-docs` in the handoff's "suggested skills" section.
  4. Embed a machine-readable seed-context block so the Mode 2 return trip can find the base seed:

     ````
     ## Seed Context
     ```json
     {
       "base_seed": "docs/seeds/<filename>",
       "open_threads": [
         {"id": "<id>", "text": "<thread text>", "first_seen_iteration": <n>}
       ],
       "disposed_threads": [
         {"id": "<id>", "text": "<thread text>", "disposition": "<decided|deferred|rejected>", "iteration": <n>}
       ]
     }
     ```
     ````
  5. Output the handoff path and stop. Do not invoke any downstream skill.

**If `status` is `"ready"` (open_threads empty):**

Run `python3 ~/.dotfiles/claude-code-shared/scripts/print-skill-next-steps.py to-seed` and print the output as the closing suggestion. Do not use `AskUserQuestion`. Output text like:

```
Seed written to docs/seeds/<filename> (status: ready)

What's next:
<skill-next-steps.py output>
```

Then stop.

**CRITICAL:** Never commit any artifact. Never push. The only things written to disk are the seed file (every run) and, when status is draft, the handoff doc.

<!-- learning-capture:start -->
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: to-seed -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `to-seed`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
**What's next:**
<!-- skill-done: to-seed -->
  - `/to-tasks` — ready to implement without a formal PRD
  - `/to-prd-html` — want a richer PRD before tasking
  - `/prototype` — exploring the idea first
<!-- learning-capture:end -->
