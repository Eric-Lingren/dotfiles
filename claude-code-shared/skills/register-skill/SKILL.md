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
```
