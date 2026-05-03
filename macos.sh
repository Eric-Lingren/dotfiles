#!/bin/bash
# macos.sh — Configure macOS system preferences
# Idempotent — safe to re-run
# Invoked optionally from install.sh

echo "Configuring macOS defaults..."

# ── Finder ──────────────────────────────────────────────────────
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"   # search current folder by default
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# ── Dock ────────────────────────────────────────────────────────
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock show-recents -bool false

# ── Keyboard ────────────────────────────────────────────────────
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false  # enable key repeat

# ── Screenshots ─────────────────────────────────────────────────
defaults write com.apple.screencapture disable-shadow -bool true
defaults write com.apple.screencapture type -string "png"

# ── General ─────────────────────────────────────────────────────
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false  # save locally by default

for app in "Finder" "Dock"; do
  killall "$app" &>/dev/null || true
done

echo "Done. Some changes require logout/restart to take effect."
