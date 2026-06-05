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

## Delegate menial work to Haiku

Push pure read-only lookups (multi-file grep/glob, "where is X", mapping a dir, reading many files to locate something, fetching a URL) to the `caveman:cavecrew-investigator` subagent (Haiku) instead of running them on the session model. Keep reasoning and edits on the session model. Skills that do heavy searching restate this; this is the default everywhere else.
