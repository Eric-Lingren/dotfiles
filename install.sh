#!/bin/bash
# install.sh — Bootstrap dotfiles on a new machine
# Usage:
#   ./install.sh            — install everything
#   ./install.sh --dry-run  — preview without making changes

set -euo pipefail

DOTFILES="$HOME/.dotfiles"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}    $*"; }
skip()    { echo -e "${GREEN}[SKIP]${RESET}    $*"; }
linked()  { echo -e "${GREEN}[LINKED]${RESET}  $*"; }
backed()  { echo -e "${YELLOW}[BACKUP]${RESET}  $*"; }

# link SRC DST — idempotent symlink creator
# Backs up existing real files, skips already-correct links
link() {
  local src="$1" dst="$2"

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    skip "$dst"
    return
  fi

  if [[ -e "$dst" && ! -L "$dst" ]]; then
    local backup="${dst}.backup.$(date +%Y%m%d%H%M%S)"
    backed "Moving existing $dst → $backup"
    $DRY_RUN || mv "$dst" "$backup"
  fi

  $DRY_RUN || mkdir -p "$(dirname "$dst")"
  $DRY_RUN || ln -sf "$src" "$dst"
  linked "$dst → $src"
}

check_prerequisites() {
  info "Checking prerequisites..."

  if ! command -v git &>/dev/null; then
    echo "Error: git is not installed. Install Xcode Command Line Tools: xcode-select --install"
    exit 1
  fi

  if ! command -v brew &>/dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh then re-run this script."
    exit 1
  fi
}

run_brewfile() {
  info "Installing Homebrew packages from Brewfile..."
  $DRY_RUN || brew bundle --file="$DOTFILES/Brewfile"

  if [[ -f "$DOTFILES/Brewfile.local" ]]; then
    info "Installing machine-local packages from Brewfile.local..."
    $DRY_RUN || brew bundle --file="$DOTFILES/Brewfile.local"
  fi
}

link_dotfiles() {
  info "Linking dotfiles..."

  # Home dotfiles
  link "$DOTFILES/.zshrc"            "$HOME/.zshrc"
  link "$DOTFILES/.gitconfig"        "$HOME/.gitconfig"
  link "$DOTFILES/.gitignore_global" "$HOME/.gitignore_global"
  link "$DOTFILES/.cmux-startup.sh"  "$HOME/.cmux-startup.sh"
  link "$DOTFILES/.scripts"          "$HOME/.scripts"

  # XDG config — individual files (not whole dirs; apps write sibling files)
  link "$DOTFILES/config/gh/config.yml"         "$HOME/.config/gh/config.yml"
  link "$DOTFILES/config/ghostty/config"         "$HOME/.config/ghostty/config"
  link "$DOTFILES/config/caveman/config.json"    "$HOME/.config/caveman/config.json"
  link "$DOTFILES/config/git/ignore"             "$HOME/.config/git/ignore"

  # Cursor IDE
  local cursor_dir="$HOME/Library/Application Support/Cursor/User"
  link "$DOTFILES/config/vscode-cursor/settings.json"    "$cursor_dir/settings.json"
  link "$DOTFILES/config/vscode-cursor/keybindings.json" "$cursor_dir/keybindings.json"
}

setup_claude_accounts() {
  info "Setting up Claude Code accounts..."

  # Shared resource dir
  link "$DOTFILES/claude-code-shared" "$HOME/.claude-code-shared"

  # Wire both accounts to the shared config
  for account in .cco .cch; do
    $DRY_RUN || mkdir -p "$HOME/$account"
    link "$DOTFILES/claude-code-shared/settings.json" "$HOME/$account/settings.json"
    link "$DOTFILES/claude-code-shared/agents"        "$HOME/$account/agents"
    link "$DOTFILES/claude-code-shared/skills"        "$HOME/$account/skills"
  done
}

setup_local_overrides() {
  info "Setting up local override files..."

  $DRY_RUN || mkdir -p "$DOTFILES/local"

  if [[ ! -f "$DOTFILES/local/zshrc.local" ]]; then
    $DRY_RUN || cp "$DOTFILES/local/zshrc.local.template" "$DOTFILES/local/zshrc.local"
    info "Created local/zshrc.local from template — edit it to customize for this machine"
  else
    skip "local/zshrc.local already exists"
  fi
}

run_macos_defaults() {
  echo ""
  local answer="n"
  [[ -t 0 ]] && read -rp "Apply macOS system defaults (Finder, Dock, keyboard)? [y/N] " answer
  if [[ "$(echo "$answer" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
    info "Applying macOS defaults..."
    $DRY_RUN || bash "$DOTFILES/macos.sh"
  else
    info "Skipping macOS defaults."
  fi
}

main() {
  echo ""
  if $DRY_RUN; then
    echo -e "${YELLOW}=== DRY RUN — no changes will be made ===${RESET}"
  else
    echo -e "${CYAN}=== Installing dotfiles ===${RESET}"
  fi
  echo ""

  check_prerequisites
  run_brewfile
  link_dotfiles
  setup_claude_accounts
  setup_local_overrides
  run_macos_defaults

  echo ""
  echo -e "${GREEN}Done!${RESET} Restart your terminal or run: source ~/.zshrc"
}

main
