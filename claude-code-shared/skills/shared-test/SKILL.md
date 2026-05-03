---
name: shared-test
description: Verify shared skills are loading from ~/.dotfiles/claude-code-shared. Run /shared-test to confirm setup.
---
<!-- TEST: In any claude session, type: /shared-test -->
<!-- Expected: confirms skill loaded, shows CLAUDE_CONFIG_DIR, shows resolved symlink path -->

Report the following, then stop:

1. Confirm: "Shared skill loaded OK"
2. Show: `CLAUDE_CONFIG_DIR` env var value
3. Show: resolved path of `~/.claude-code-shared/skills` symlink
4. Show: current account context (work = `~/.ccw`, home = `~/.ccp`)
