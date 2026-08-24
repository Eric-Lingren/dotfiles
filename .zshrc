export ZSH="$HOME/.oh-my-zsh"


# ─────────────────────────────────────────#
# OH MY ZSH — core settings                #
# ─────────────────────────────────────────#

# Auto-update behavior (auto/reminder/disabled)
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 13

# Uncomment if pasting URLs or text behaves oddly
# DISABLE_MAGIC_FUNCTIONS="true"

plugins=(git node fnm macos z)
# ZSH_THEME="steeef"
ZSH_THEME="bira"
# ZSH_THEME="avit"
# ZSH_THEME="sorin"
source $ZSH/oh-my-zsh.sh



# ─────────────────────────────────────────#
# ENVIRONMENT                              #
# ─────────────────────────────────────────

# Default editor for git commits, crontab, etc.
export EDITOR='nano'
# Isolate history to the current terminal
unset HISTFILE
setopt INC_APPEND_HISTORY
setopt NO_SHARE_HISTORY

# Uncomment to set timestamp format (mm/dd/yyyy | dd.mm.yyyy | yyyy-mm-dd)
# HIST_STAMPS="mm/dd/yyyy"



# ─────────────────────────────────────────#
# PATH additions                           #
# ─────────────────────────────────────────#

export PATH="$HOME/.console-ninja/.bin:$PATH"
export PATH="/Applications/Ghostty.app/Contents/MacOS:$PATH"
export PATH="$HOME/.scripts:$PATH"
# Editor CLI shims. VS Code owns `code`; Cursor aliased so its bundled
# `code` binary cannot shadow it.
export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"
alias cursor="/Applications/Cursor.app/Contents/Resources/app/bin/cursor"



# ─────────────────────────────────────────#
# ALIASES                                  #
# ─────────────────────────────────────────#

alias reload="source ~/.zshrc"
alias ls='eza --color=always --icons'
alias runcelery="celery -A task.celery worker --loglevel=info -Q user_waiting,notifications,integrations,longtasks,whenever,celery,email_parsing,doc_parsing"
alias celery="celery -A task.celery worker --loglevel=info -Q user_waiting,notifications,integrations,longtasks,whenever,celery,email_parsing,doc_parsing"


# ─────────────────────────────────────────#
# HISTORY                                  #
# ─────────────────────────────────────────#

HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS    # don't save duplicate commands
setopt SHARE_HISTORY       # share history across terminal sessions



# ─────────────────────────────────────────#
# NODE — version management (fnm)          #
# ─────────────────────────────────────────#

# Auto-switches Node version when entering a directory with .node-version or .nvmrc
eval "$(fnm env --use-on-cd)"



# ─────────────────────────────────────────#
# Project — Quaestor Web                   #
# ─────────────────────────────────────────#
# Loads project-specific aliases and env vars for Quaestor Web dev environment

source ~/Documents/dev/Quaestor-Web/dev/.zshrc

# New cmux tabs inherit the parent pane's CWD. Opening a fresh workspace from
# inside a worktree would start you in that worktree instead of clean, so reset
# to the main repo root.
#
# Editor terminals are exempt. Cursor and VS Code both report TERM_PROGRAM=vscode
# and root their integrated terminal in the folder the window has open, which for
# a worktree window is the worktree itself. Without this guard the rc file cds
# out of it and the terminal reports the main clone instead. cmux reports
# TERM_PROGRAM=ghostty.
if [[ "$PWD" == */worktrees/* && "$TERM_PROGRAM" != "vscode" ]]; then
  cd ~/Documents/dev/Quaestor-Web
fi



# ─────────────────────────────────────────#
# FUNCTIONS                                #
# ─────────────────────────────────────────#

function wt {
  local output exit_code target
  output=$("$HOME/.dotfiles/.scripts/worktree" "$@")
  exit_code=$?
  if [[ $exit_code -eq 0 && -n "$output" ]]; then
    target=$(printf '%s' "$output" | tail -1)
    cd "$target"
    local _wt_branch=""
    for _wt_arg in "$@"; do
      if [[ "$_wt_arg" != --* && "$_wt_arg" != "ls" && "$_wt_arg" != "rm" && "$_wt_arg" != "-h" && "$_wt_arg" != "--help" ]]; then
        _wt_branch="$_wt_arg"
        break
      fi
    done
    local _wt_identity _wt_surface _wt_workspace
    _wt_identity=$(cmux identify 2>/dev/null)
    _wt_surface=$(printf '%s' "$_wt_identity" | grep -o 'surface:[0-9]*' | head -1)
    _wt_workspace=$(printf '%s' "$_wt_identity" | grep -o 'workspace:[0-9]*' | head -1)
    if [[ -n "$_wt_branch" ]]; then
      local _wt_label="${_wt_branch#feat/}"
      _wt_label="${_wt_label#fix/}"
      _wt_label="${_wt_label#spike/}"
      _wt_label="🌿 $_wt_label"
      ZSH_THEME_TERM_TITLE_IDLE="$_wt_label"
      ZSH_THEME_TERM_TAB_TITLE_IDLE="$_wt_label"
      [[ -n "$_wt_surface" ]] && cmux rename-tab --surface "$_wt_surface" "$_wt_label" 2>/dev/null || true
      [[ -n "$_wt_workspace" ]] && cmux rename-workspace --workspace "$_wt_workspace" "$_wt_label" 2>/dev/null || true
    fi
    if [[ -n "$_wt_surface" && -n "$_wt_workspace" ]]; then
      local _wt_split
      _wt_split=$(cmux new-split right --surface "$_wt_surface" --workspace "$_wt_workspace" 2>/dev/null | grep -o 'surface:[0-9]*' | head -1)
      if [[ -n "$_wt_split" ]]; then
        [[ -n "$_wt_label" ]] && cmux rename-tab --surface "$_wt_split" "$_wt_label" 2>/dev/null || true
        cmux send --surface "$_wt_split" "cd $(printf '%q' "$target")" 2>/dev/null
        cmux send-key --surface "$_wt_split" Return 2>/dev/null
      fi
    fi
  fi
}

function runserver {
  cd ~/Documents/dev/Quaestor-Web/app
  dev aws-refresh-env
  python manage.py runserver_plus --keep-meta-shutdown
}

function runclient {
  cd ~/Documents/dev/Quaestor-Web/client
  yarn dev
}

function migrate {
  cd ~/Documents/dev/Quaestor-Web/app
  python manage.py migrate
}



# ─────────────────────────────────────────#
# CLAUDE CODE — multi-account aliases      #                                         
# ─────────────────────────────────────────#
 
alias cco="CLAUDE_CONFIG_DIR=$HOME/.cco $HOME/.cco-npm/bin/claude"
alias cch="CLAUDE_CONFIG_DIR=$HOME/.cch $HOME/.cch-npm/bin/claude"

# Per-instance updaters (isolated npm prefixes, zero cross-pollution)
alias cch-update="npm install -g --prefix $HOME/.cch-npm @anthropic-ai/claude-code@latest"
alias cco-update="npm install -g --prefix $HOME/.cco-npm @anthropic-ai/claude-code@latest"
alias cch-doctor="CLAUDE_CONFIG_DIR=$HOME/.cch $HOME/.cch-npm/bin/claude doctor"
alias cco-doctor="CLAUDE_CONFIG_DIR=$HOME/.cco $HOME/.cco-npm/bin/claude doctor"

# Update both instances at once (auto-updater disabled; update is manual by design)
alias cc-update="npm install -g --prefix $HOME/.cco-npm @anthropic-ai/claude-code@latest && npm install -g --prefix $HOME/.cch-npm @anthropic-ai/claude-code@latest && echo \"cco: \$($HOME/.cco-npm/bin/claude --version) | cch: \$($HOME/.cch-npm/bin/claude --version)\""

# Disable bare `claude` to avoid accidentally using the wrong account
alias claude="echo 'Use cco (office) or cch (home). Update both: cc-update'"



# ─────────────────────────────────────────#
# CMUX SETTINGS                            #
# ─────────────────────────────────────────#
# Run startup script once per cmux session using a lockfile

if [ -n "$CMUX_WORKSPACE_ID" ]; then
  BOOT_TIME=$(sysctl -n kern.boottime | awk '{print $4}' | tr -d ',')
  SESSIONLOCK="/tmp/cmux-session-${BOOT_TIME}.lock"
  if [ ! -f "$SESSIONLOCK" ]; then
    rm -f /tmp/cmux-session-*.lock 2>/dev/null
    touch "$SESSIONLOCK"
    ~/.cmux-startup.sh > /tmp/cmux-startup.log 2>&1 &
    trap 'rm -f /tmp/cmux-session-*.lock' EXIT  # only set in the first shell
  fi
fi

# \e[2 q = steady block cursor
_fix_cursor() { echo -ne '\e[1 q'; }
precmd_functions+=(_fix_cursor)


# Weekly Claude Code usage digest nudge (once per new report). Re-read: ccusage
[[ -f ~/.dotfiles/claude-code-shared/scripts/cc-usage-nudge.sh ]] && \
  source ~/.dotfiles/claude-code-shared/scripts/cc-usage-nudge.sh


# ─────────────────────────────────────────#
# gx git toolkit                           #
# ─────────────────────────────────────────#

export GX_SCRIPTS_DIR="$HOME/.dotfiles/.scripts"
alias gxcheck="$GX_SCRIPTS_DIR/gxcheck"
alias gxpush="$GX_SCRIPTS_DIR/gxpush"
alias gxmove="$GX_SCRIPTS_DIR/gxmove"
alias gxclean="$GX_SCRIPTS_DIR/gxclean"
alias gxsync="$GX_SCRIPTS_DIR/gxsync"
alias pr-commit="$GX_SCRIPTS_DIR/pr-commit"
alias pr-desc="$GX_SCRIPTS_DIR/pr-desc"


# ─────────────────────────────────────────#
# MACHINE-LOCAL OVERRIDES                  #
# ─────────────────────────────────────────#
# Gitignored — see local/zshrc.local.template

[[ -f ~/.dotfiles/local/zshrc.local ]] && source ~/.dotfiles/local/zshrc.local
