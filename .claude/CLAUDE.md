# Global Claude Code Rules

## Shared scripts and resources

All shared scripts and resources live at `~/.dotfiles/claude-code-shared/`.

**Never reach for `~/.cch/`, `~/.cco/`, `~/.claude/`, or any other directory when looking for shared scripts.**

If a skill instructs you to run a script from `~/.dotfiles/claude-code-shared/scripts/` and the script is not found there, stop and tell the user. Do not guess alternate locations or silently fall back to a different path.

Key shared paths:
- Scripts: `~/.dotfiles/claude-code-shared/scripts/`
- Skills: `~/.dotfiles/claude-code-shared/skills/`
- Resources: `~/.dotfiles/claude-code-shared/resources/`
