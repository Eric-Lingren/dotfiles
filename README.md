# dotfiles

## New Machine Setup

```bash
git clone https://github.com/Eric-Lingren/dotfiles ~/.dotfiles
cd ~/.dotfiles && ./install.sh
```

Preview without making changes:
```bash
./install.sh --dry-run
```

## What's Here

- `.zshrc` — Shell config (Oh My Zsh, fnm, aliases, functions)
- `Brewfile` — Homebrew packages (`brew bundle` installs everything)
- `config/` — App configs (Ghostty, Cursor, gh, git, caveman)
- `claude-code-shared/` — Shared Claude Code hooks, skills, agents
- `.scripts/` — Shell utilities (`pr-desc`: Claude-powered PR description generator)
- `install.sh` — Bootstrap script: symlinks, Homebrew, Claude Code accounts
- `macos.sh` — macOS system preference defaults (Finder, Dock, keyboard)

## Machine-Local Config

`local/` is gitignored. `install.sh` creates `local/zshrc.local` from the template on first run — edit it to set machine-specific env vars:

```bash
# local/zshrc.local
export CC_WORK_DIR="$HOME/.cco"   # which Claude account pr-desc uses
```

## Claude Code Accounts

Two accounts managed via `CLAUDE_CONFIG_DIR`:

| Alias | Account | Config dir |
|-------|---------|------------|
| `cco` | Office  | `~/.cco`   |
| `cch` | Home    | `~/.cch`   |

Both accounts share settings, hooks, skills, and agents from `claude-code-shared/`.
