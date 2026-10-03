# Global Claude Code Rules

## Shared scripts and resources

All shared scripts and resources live at `~/.dotfiles/claude-code-shared/`.

**Never reach for `~/.cch/`, `~/.cco/`, `~/.claude/`, or any other directory when looking for shared scripts.**

If a skill instructs you to run a script from `~/.dotfiles/claude-code-shared/scripts/` and the script is not found there, stop and tell the user. Do not guess alternate locations or silently fall back to a different path.

Key shared paths:
- Scripts: `~/.dotfiles/claude-code-shared/scripts/`
- Skills: `~/.dotfiles/claude-code-shared/skills/`
- Resources: `~/.dotfiles/claude-code-shared/resources/`

**Exception — gx git toolkit:** Skills may invoke `~/.dotfiles/.scripts/gx*` verbs (`gxcheck`, `gxpush`, `gxmove`, `gxclean`, `gxsync`) via absolute path `~/.dotfiles/.scripts/<verb>`. These are intentionally outside `claude-code-shared/` and the path restriction above does not apply to them.

## Scriptable-code rule

If something is mechanical and scriptable, it lives in code. Bash operations, API calls, token checks, and external writes must be implemented as scripts in `claude-code-shared/scripts/` with real argument handling. Do not leave these as inline prose, template comments, or copy-paste blocks inside skill or agent files.

## Eval reports always get a plain-English summary

Whenever you build or rebuild an eval report (claude-api `build-eval` / `hillclimb`, or any `.claude/hillclimb/<flow>/` directory), run `~/.dotfiles/claude-code-shared/scripts/eval-report.sh <flow-dir>` instead of calling the report builder directly. It writes `report.html` and `summary.html` (plain-English page). Hand the user `summary.html` first, then `report.html` for detail. For a new eval, fill `_state.json`'s `summary` block (`what`, `metrics`, `kinds`, `groups`, `case_notes`); see the script header for the shape. Eval transcripts and fixtures hold source from other repos: never commit `traces/`, `ref/`, `fixtures/`, `report.html`, or `summary.html` (ignored via `.gitignore` and `repo-policy.json` excludes). Agent-bench results (`/improve-agent-benchmarks`) get their plain-English summary from `~/.dotfiles/claude-code-shared/scripts/agent-eval/summary.py <agent>` (writes `.claude/agent-bench/<agent>/summary.html`), not from `eval-report.sh`.

## Delegate menial work to Haiku

Push pure read-only lookups (multi-file grep/glob, "where is X", mapping a dir, reading many files to locate something, fetching a URL) to the `caveman:cavecrew-investigator` subagent (Haiku) instead of running them on the session model. Keep reasoning and edits on the session model. Skills that do heavy searching restate this; this is the default everywhere else.
