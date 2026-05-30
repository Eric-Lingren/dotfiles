# Skill model-tiering

Each skill runs on a deliberate model + effort level, chosen by cognitive
complexity. One config drives it. Skills can never drift from that config.

## The tiers

| Tier | Model | Effort | For |
|------|-------|--------|-----|
| T1 | haiku | low | Pure lookup. No reasoning. (`how-to`, `find-work`) |
| T2 | sonnet | medium | Mechanical, narrow scope. (`tasks-to-linear`, `run-task-followups`) |
| T3 | sonnet | xhigh | Standard build. **Session default.** (most skills) |
| T4 | opus | xhigh | Deep reasoning. (`grill-me`, `grill-with-docs`, `debug`, `improve-codebase-architecture`) |

Session default is set in `settings.json` (`"model": "sonnet"`, `"effortLevel": "xhigh"`),
so ad-hoc prompts run T3. Skills override via their own frontmatter.

## Moving parts

| File | Role |
|------|------|
| `resources/skill-tiers.json` | **Source of truth.** Tier definitions + per-skill assignment + delegate list. |
| `scripts/sync-skill-tiers.py` | Stamps `model:`/`effort:` into each skill's frontmatter + injects delegation blocks. |
| `.githooks/pre-commit` | Auto-runs the sync on every commit. Re-stages anything it changed. No drift, ever. |
| `hooks/tier-advisor.sh` | `UserPromptSubmit` advisory. Nudges `/model opus` (deep) or `/model haiku` (lookup). |
| each `skills/*/SKILL.md` | Carries explicit `model:`/`effort:` (stamped, do not hand-edit). |

## Re-tiering a skill

1. Edit `resources/skill-tiers.json` (move a skill between tiers, or change what a tier's model/effort is).
2. `python3 ~/.dotfiles/claude-code-shared/scripts/sync-skill-tiers.py --check`  (preview)
3. `... --apply`  (write).

Or just edit the json and commit. The pre-commit hook applies it for you.

## Delegation

Skills in the config's `delegate` list get a block telling them to push menial
read-only lookups (grep/glob/read-many/fetch) to the `caveman:cavecrew-investigator`
subagent (Haiku) instead of burning the session model. A thin backstop rule lives
in the global `CLAUDE.md`.

## The advisory hook

`hooks/tier-advisor.sh` fires on each prompt:
- Deep-reasoning signals (architecture, hard debug, tradeoffs) -> suggests `/model opus`.
- Pure lookups (`where is`, `how do i`, `list all`) with no action verb -> suggests `/model haiku`.
- Everything else -> silent.

It never switches the model itself (hooks can't set the current turn's model). It
only nudges. Disable with `export CLAUDE_TIER_ADVISOR=0`.

## Fresh clone setup (one-time)

The pre-commit hook is tracked but activated by repo-local config. After cloning:

```bash
git config core.hooksPath .githooks
```

Skip the hook for one commit with `git commit --no-verify`.
