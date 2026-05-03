# ── Core CLI Tools ─────────────────────────────────────────────
brew "eza"           # Modern ls replacement
brew "ripgrep"       # Fast grep
brew "gh"            # GitHub CLI

# ── Node.js ─────────────────────────────────────────────────────
brew "fnm"           # Fast Node Manager
brew "pnpm"
brew "yarn", link: false

# ── Python / Backend ────────────────────────────────────────────
brew "postgresql@17", restart_service: :changed, link: true
brew "redis",         restart_service: :changed
brew "mailhog"       # SMTP testing
brew "moto",          restart_service: :changed  # Mock AWS services

# ── AWS / Kubernetes ────────────────────────────────────────────
tap "supabase/tap"
brew "aws-iam-authenticator"
brew "kubectx"
brew "supabase/tap/supabase"

# ── Apps / Fonts ────────────────────────────────────────────────
cask "ngrok"
cask "font-jetbrains-mono"
