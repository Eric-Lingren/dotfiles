---
name: register-skill
description: Register a new skill or agent into the shared infrastructure so tier-advisor, the weekly usage report, and sync-model-tiers never miss it. Invoke as /register-skill <name>. Covers both the skill registration path (tiered via model-tiers.json skills map) and the agent registration path (tiered via model-tiers.json agents map). This file is the canonical reference for the full registration chain.
model: sonnet
effort: medium
---

# Register Skill

Wire a new skill or agent into the shared infrastructure so every hook, advisor, and report picks it up automatically.

## The full registration chain (canonical reference)

Two separate paths depending on whether you are registering a **skill** or an **agent**.

### Skill path

Skills are tracked by two hooks, both of which read `claude-code-shared/resources/model-tiers.json`:

1. **tier-advisor.sh** (UserPromptSubmit hook) — looks up the skill name in `model-tiers.json`. If missing: no model/effort nudge fires when the user invokes the skill.
2. **cc-usage-benchmark.py** (usage analytics) — builds `expected_model` from `cfg["skills"]`. If missing: the skill is silently absent from the weekly tier-adherence report.
3. **sync-model-tiers.py** — stamps `model:` and `effort:` into each skill's `SKILL.md` frontmatter from the tier map. Runs via `--apply` flag and also via the pre-commit hook automatically on commit.

A skill is not fully registered until all three are satisfied.

### Agent path

Agents live in `claude-code-shared/agents/`. They are tiered via the `agents` map in
`model-tiers.json`. The sync script (`sync-model-tiers.py`) stamps the tier's `model:`
into the agent's frontmatter and updates the matching `registry.json` entry — so the
agent never drifts from its assigned tier.

An agent is fully registered when:
- The file exists in `claude-code-shared/agents/<name>.md`
- Frontmatter has: `name`, `description`, `tools`
- The agent is assigned a tier in `model-tiers.json`'s `agents` map
- The sync has been run (or will run via the pre-commit hook)
- A `registry.json` entry exists with the correct `model` field

**Agents consume model only.** Effort is a session concept and is never stamped into agent frontmatter.

---

## Steps

### 1. Detect target type

Check whether the target exists as a skill or an agent:

```bash
ls claude-code-shared/skills/<name>/SKILL.md   # skill
ls claude-code-shared/agents/<name>.md          # agent
```

If neither exists, stop and tell the user: the file must exist before registering.

If both exist (unusual), ask the user which path they want to register.

### 1b. Skill path — format contract gate (hard-FAIL)

> Architecture overview: `claude-code-shared/contracts/overview.html`

Before proceeding with registration, grep the SKILL.md for format signals that indicate the skill touches a shared contract format:

```bash
grep -E "docs/tasks/|docs/seeds/|-schema\.json|contracts/" \
  claude-code-shared/skills/<name>/SKILL.md
```

**If any signal is found:** also check whether the file contains a `## Contract` section with a `validate-schema.sh` line:

```bash
grep -c "## Contract" claude-code-shared/skills/<name>/SKILL.md
grep -c "validate-schema.sh" claude-code-shared/skills/<name>/SKILL.md
```

**Decision:**
- **Signal found AND both checks pass (Contract section + validate-schema.sh line present):** proceed to step 2a.
- **Signal found AND either check fails:** HARD-FAIL. Print:

  ```
  ERROR: Registration blocked.
  <name>/SKILL.md references a shared format (docs/tasks/, docs/seeds/, *-schema.json, or contracts/)
  but is missing a ## Contract section with a validate-schema.sh Step-0 invocation.

  Add a ## Contract section. See contracts/task-contract.md (or seed-contract.md, runner-result-contract.md)
  for the required section format. Re-run /register-skill after adding it.
  ```

  Stop. Do not proceed with registration.

- **No signal found:** skip this check entirely. Proceed to step 2a.

This gate ships as hard-FAIL. There is no WARN fallback.

### 1c. Skill path — update interactive diagram (format-touching skills only)

Skip this step if step 1b found no format signals.

If the skill touches a shared format, add it to `claude-code-shared/contracts/overview.html`. Open the file and locate the Mermaid flowchart. Add the skill node to the correct subgraph:

- **Planning** — skills that produce or consume `seed.json` or `HTML PRD`
- **Tasking** — skills that produce `task.json`
- **Execution** — skills that consume `task.json` or produce `verdict`
- **Triaging** — skills that consume `task.json` for tracking/routing

Add the node with a quoted label:

```
skillId["/skill-name"]
```

Add edges reflecting the actual data flow (solid `-->` for unconditional, dashed `-.->` for conditional). Add the new node ID to the `class ... skill` line at the bottom of the classDef block.

After editing, open the file in a browser and confirm the diagram renders without syntax errors before proceeding.

### 2a. Skill path — choose a tier

Read `claude-code-shared/resources/model-tiers.json` — it is the source of truth for all tier definitions. The `tiers` map contains each tier's model, effort, and meaning. Present those to the user directly from the file rather than from a hardcoded table here.

Read the skill's `description:` field from its `SKILL.md` frontmatter. Recommend a tier based on what it does:
- T1: lookup, navigation, status display
- T2: thin shim, mechanical delegation, well-defined transform
- T3: multi-step reasoning, code writing, context-aware decisions
- T4: architecture, deep debugging, design sessions

Ask the user to confirm the tier or choose a different one.

### 2b. Skill path — decide delegate membership

Ask: "Does this skill do heavy read-only searching or web fetching itself (not via a spawned agent)?"

If yes: add it to the `delegate` array in `model-tiers.json`. This causes `sync-model-tiers.py` to inject the managed Haiku-delegation block into the skill's frontmatter.

If no (the skill delegates to an agent, or does no heavy lookups): do NOT add to `delegate`.

### 2c. Skill path — producer enum upkeep (lineage producers only)

**Ask:** "Does this skill write a task file, seed, PRD, or any other artifact that participates in the provenance lineage chain?"

If yes (it is a lineage producer): edit `claude-code-shared/contracts/provenance-schema.json` and add the skill name to `$defs.producer.enum`. This is the closed enum of every skill that can appear as `producer` in a lineage document:

```json
"$defs": {
  "producer": {
    "enum": [
      ...,
      "<new-skill-name>"
    ]
  }
}
```

The skill name added here must exactly match the skill's directory name under `skills/` and the name it will write into the `producer` field of its output documents.

Run `validate-schema.sh contracts/provenance-schema.json` afterward to confirm the schema is still valid:
```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  ~/.dotfiles/claude-code-shared/contracts/provenance-schema.json
```

If no (it is not a lineage producer — a pure reader, reviewer, or advisor): skip this step.

### 2d. Skill path — edit model-tiers.json

Add the skill name to the `skills` map at the confirmed tier:

```json
"skills": {
  ...
  "<skill-name>": "T2"
}
```

If adding to `delegate`, also add to that array:

```json
"delegate": [
  ...,
  "<skill-name>"
]
```

### 2e. Skill path — run sync

```bash
# Preview first
python3 claude-code-shared/scripts/sync-model-tiers.py --check

# Apply — stamps model: and effort: into the skill's SKILL.md frontmatter
python3 claude-code-shared/scripts/sync-model-tiers.py --apply
```

### 2f. Skill path — verify

Run these checks:

```bash
# 1. Tier-advisor resolves the skill
echo '{"prompt": "/<skill-name>"}' | bash claude-code-shared/hooks/tier-advisor.sh

# 2. Frontmatter was stamped
head -6 claude-code-shared/skills/<skill-name>/SKILL.md

# 3. model-tiers.json is consistent
python3 claude-code-shared/scripts/sync-model-tiers.py --check
```

Confirm `tier-advisor.sh` emits the advisory block with the correct tier. If it prints nothing for the skill name, the name in `model-tiers.json` does not match the slash-command name — fix the mismatch.

To confirm the weekly usage report will count it: the benchmark uses `SKILL_BODY_RE = re.compile(r"skills/([a-z0-9-]+)/SKILL\.md", re.I)` to extract skill names from transcript paths. The skill name in `model-tiers.json` must match the directory name under `skills/` exactly.

### 2g. Skill path — learning capture integration

Stamp the new skill with the managed learning-capture tail block and register it as a learning producer.

**Step 1 — inject the tail block:**

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/inject-learning-tail.py \
  --apply --skills-dir ~/.dotfiles/claude-code-shared/skills
```

The script only modifies skills that are missing the block. Running it after step 2e is safe and idempotent.

**Step 2 — add the skill to the producers list in learning-contract.md:**

Edit `claude-code-shared/contracts/learning-contract.md`. Locate the `## Producers` section and add a line for the new skill in alphabetical order:

```
- `skills/<new-skill-name>/`
```

The new skill name must exactly match the directory name under `skills/`.

### 3. Agent path — assign a tier in model-tiers.json

Read `claude-code-shared/resources/model-tiers.json` and add the agent to the `agents` map:

```json
"agents": {
  ...
  "<agent-name>": "T1"
}
```

Choose the tier by the same criteria as skills. Agents are typically T1 (lookup-only,
no reasoning), T3 (context-aware, moderate capability), or T3-T4 for complex tasks.
**Remember: only the `model` from the tier is used — effort is ignored for agents.**

After editing the JSON, run the sync:

```bash
# Preview
python3 claude-code-shared/scripts/sync-model-tiers.py --check

# Apply — stamps model: into the agent's frontmatter and updates registry.json
python3 claude-code-shared/scripts/sync-model-tiers.py --apply
```

### 3b. Agent path — verify frontmatter

Read the agent file and confirm it has all required fields:

```bash
head -8 claude-code-shared/agents/<name>.md
```

Required frontmatter:
- `name:` — must match the filename (without `.md`)
- `description:` — used by Claude to decide when to spawn this agent
- `tools:` — comma-separated list of tools the agent may use
- `model:` — stamped by the sync from the tier; do not hand-edit

If `name`, `description`, or `tools` are missing, edit the agent file to add them.
Do not hand-edit `model:` — the sync owns that field.

### 3c. Agent path — update registry.json

After verifying frontmatter, upsert the agent into `claude-code-shared/agents/registry.json`:

```bash
python3 claude-code-shared/scripts/registry_sync.py \
  claude-code-shared/agents/registry.json \
  '{"name":"<name>","file":"agents/<name>.md","model":"<model>","description":"<description>","consumers":["<skill-1>","<skill-2>"]}'
```

Ask the user: "Which skills consume this agent?" Use their answer for the `consumers` list. If unknown, use `[]` and note it can be updated later.

After the upsert, run validate-registry.py to confirm consistency:

```bash
python3 claude-code-shared/scripts/validate_registry.py
```

If validation fails, fix the registry before proceeding.

### 4. Report

Print a short summary:

```
Registered: <name> (<skill|agent>)
  Type:    <skill | agent>
  Tier:    <T1-T4>
  Model:   <model>
  Effort:  <effort | n/a (agents use model only)>
  Delegate: <yes | no | n/a (agent)>
  Hooks:   tier-advisor ✓  usage-benchmark ✓  sync ✓   (skill)
           usage-benchmark ✓  sync ✓  tier-advisor n/a  (agent)
  Learning: tail-block ✓  producers-list ✓              (skill only)
```

<!-- learning-capture:start -->
## Learning Capture

**Default: write nothing.** Most runs record nothing. Only proceed if an observable
correction-event occurred this run — a tool failure you had to work around, a backtrack,
a user correction, an instruction gap, or redundant work you repeated.

### Step 1 — assess whether a correction-event occurred

If no correction-event: stop here. Do not call the judge. Do not call the writer.

### Step 2 — build a candidate entry

Construct this JSON object (do not include schema_version or timestamp; the writer injects them):

```json
{
  "skill": "<this skill's slug, e.g. debug>",
  "trigger": "<tool_failure | backtrack | user_correction | instruction_gap | redundant_effort | uncategorized>",
  "trigger_label": "<snake_case label if trigger == uncategorized, else null>",
  "evidence": "<WHAT happened this run. Observable, run-specific. For aggregated events (redundant_effort, backtrack, or any tried-N-times observation) list discrete quoted transcript anchors — not a bare count. The judge counts len(anchors).>",
  "learning": "<WHY it happened and the general reusable rule that must hold beyond this run. If this sentence only describes this run it belongs in evidence, not here.>",
  "suggested_fix": "<the concrete skill or script edit that would prevent recurrence, or null>"
}
```

Enumerate-discrete-anchors: for any aggregated observation, evidence must quote each
individual anchor explicitly. Example — correct: "Ran Glob three times: step 2 ('no
results'), step 5 ('no results'), step 8 ('found debug.jsonl')." Incorrect: "Ran Glob
three times without finding the file."

### Step 3 — grounding gate

Spawn the `learning-grounding-judge` agent (`subagent_type: learning-grounding-judge`,
model: haiku). Pass it:

```
## Entry
<candidate entry JSON>

## Transcript path
<absolute path to the session transcript file>
```

The agent returns `{"grounded": true|false, "reason": "..."}`.

### Step 4 — write or discard

If `grounded: true`:
```bash
echo '<entry JSON>' | python ~/.dotfiles/claude-code-shared/scripts/log-learning.py
```

If `grounded: false`: write nothing. The agent's reason explains what anchor was missing.
<!-- learning-capture:end -->
