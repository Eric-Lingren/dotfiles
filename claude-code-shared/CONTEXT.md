# CONTEXT — claude-code-shared

This repo is the shared Claude Code tooling layer: skills, agents, contracts, hooks,
resources, and scripts consumed by both the `.cch` (personal) and `.cco` (work) Claude
Code profiles. It is infra, not a product codebase — there is no runtime app here, only
markdown-defined behaviors, JSON registries/contracts, and small executable scripts that
enforce or automate them.

## Noun glossary

- **Skill** — a directory under `skills/<name>/` containing a `SKILL.md` (frontmatter +
  instructions) that Claude loads on trigger match. May include `scripts/`, `resources/`,
  `assets/`, or `runs/` subdirectories per `resources/skill-directory-conventions.md`.
  Registered in `resources/model-tiers.json` under `skills`.
- **Agent** — a subagent defined by a `.md` file under `agents/<name>.md` (frontmatter:
  name, description, tools, model) that a skill spawns via the Agent tool for a bounded,
  stateless piece of work (e.g. `context-loader`, `lint-runner`, `browser-checker`).
  Every agent must be listed in `agents/registry.json`, which is the **source of truth**
  for what agents exist, their model, and their consumer skills.
- **Contract** — a paired `.md` (human-readable spec) + `.json` schema file under
  `contracts/` that defines the exact shape of data passed between a skill and an agent,
  or between pipeline stages (e.g. `seed-contract.md`/`seed-schema.json`,
  `task-contract.md`/`task-schema.json`, `runner-result-contract.md`/`-schema.json`).
  Agents and skills must produce/consume data matching these shapes exactly — contracts
  are the interface boundary, not documentation of intent.
- **Hook** — a shell/python script under `hooks/` wired into a Claude Code profile's
  `settings.json` (`PreToolUse`, `Stop`, etc.) that runs automatically around tool calls
  (e.g. `block-destructive-git.sh`, `tier-advisor.sh`, `stop-hook.py`). Hooks are the only
  mechanism for enforcing "always/never" behaviors — they run in the harness, not as
  model-followed instructions, so they can't be talked out of firing.
- **Resource** — a reference file under `resources/` (or a skill-local `resources/`)
  that a skill or agent reads for extra structured context: format guides, runbooks,
  or config-shaped JSON (`model-tiers.json`, `task-routing.json`, `repo-policy.json`).
  Not user-facing docs — these are inputs to skill/agent logic.
- **Registry** — `agents/registry.json`. The authoritative list of every agent: name,
  file path, model, description, and consumer skills. Anything spawning an agent not
  listed here is spawning an unregistered agent; `register-skill` exists to keep this
  file (and `model-tiers.json`) in sync when a new skill or agent is added.
- **Pipeline stage** — one node in the workflow DAG defined by `skill-pipeline.json`
  (`skills[<slug>].next: [{skill, when}]`). Encodes which skill logically follows
  another (e.g. `to-seed` → `to-tasks` → `dispatch-tasks`) so `inject-learning-tail.py`
  can bake an accurate "next step" suggestion into each skill's closing output.
- **Tier** — a model+effort pairing (T1–T4) defined in `resources/model-tiers.json`,
  keyed by skill name (`skills` map) or agent name (`agents` map). T1 = haiku/low
  (lookup), T2 = sonnet/medium (mechanical), T3 = sonnet/high (session default,
  context-aware build), T4 = opus/xhigh (deep reasoning). `scripts/sync-model-tiers.py`
  is the only thing that should propagate tier changes into skill/agent frontmatter.

## Load-bearing invariants

1. **Absolute-path script references.** Skills and agents must invoke shared scripts
   via the absolute path `~/.dotfiles/claude-code-shared/scripts/<name>` (or the fully
   resolved `/Users/<user>/.dotfiles/...` form), never a relative path or a guessed
   alternate location (`~/.cch/`, `~/.cco/`, `~/.claude/`). If a referenced script is
   missing at that path, stop and surface it — don't silently fall back elsewhere.
2. **`agents/registry.json` is the source of truth for agents.** Every agent that can be
   spawned must have an entry here (name, file, model, description, consumers). Tooling
   (tier-advisor, weekly usage report, sync-model-tiers) reads this file, not the agent
   `.md` frontmatter, to know an agent exists.
3. **`resources/model-tiers.json` keys skills and agents by name.** Both the `skills`
   map and `agents` map must stay in sync with what's actually registered/present on
   disk, or tier-advisor and the usage report will silently miss items. Apply changes
   via `scripts/sync-model-tiers.py --apply`, not by hand-editing frontmatter alone.
4. **`.cch` and `.cco` are symlink farms into this repo, not independent copies.**
   `~/.cch/skills` and `~/.cco/skills` symlink to `~/.claude-code-shared/skills` (itself
   pointing at `claude-code-shared/` in this dotfiles repo), and likewise for `agents/`
   and `settings.json`. There is exactly one copy of every skill/agent/setting; editing
   under `.cch/` or `.cco/` directly edits this repo through the symlink.
5. **Hooks are wired via `settings.json`, not auto-discovered.** A script dropped into
   `hooks/` does nothing until it's registered under the matching `PreToolUse`/`Stop`
   array in `settings.json` (see `block-destructive-git.sh`, `tier-advisor.sh`, etc. in
   the current wiring). Adding a hook file without wiring it is a no-op.
6. **Contracts gate agent I/O.** A skill spawning an agent must shape its prompt to
   match the agent's expected input, and treat the agent's response as matching the
   contract's output schema — validate against `contracts/<name>-schema.json` when in
   doubt, not against what the agent happened to return.

## Context Sources

- `agents/registry.json` — canonical agent list
- `resources/model-tiers.json` — tier assignments for skills and agents
- `skill-pipeline.json` — pipeline stage DAG
- `resources/skill-directory-conventions.md` — skill subdirectory layout rules
- `resources/repo-policy.json` — per-repo branching/domain policy consumed by branching flows
