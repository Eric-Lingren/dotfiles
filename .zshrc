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

# Wrap the repo's `dev` function so `dev start` runs a preflight first: it
# repairs/installs node_modules and clears stale servers on :3000/:8000.
# The repo's dev/.zshrc is team-owned, so the wrapper lives here.
# Bypass: DEV_PREFLIGHT=0 dev start
if (( $+functions[dev] )) && ! (( $+functions[_repo_dev] )); then
  functions -c dev _repo_dev
  dev() {
    if [[ "$1" == start && "${DEV_PREFLIGHT:-1}" != 0 ]]; then
      ~/.dotfiles/.scripts/dev-preflight || return 1
    fi
    _repo_dev "$@"
  }
fi

# New cmux tabs inherit the parent pane's CWD. Opening a fresh workspace from
# inside a worktree would start you in that worktree instead of clean, so reset
# to the main repo root.
#
# Editor terminals are exempt. Cursor and VS Code both report TERM_PROGRAM=vscode
# and root their integrated terminal in the folder the window has open, which for
# a worktree window is the worktree itself. Without this guard the rc file cds
# out of it and the terminal reports the main clone instead. cmux reports
# TERM_PROGRAM=ghostty.
#
# GX_WORKTREE_TARGET: set by gxstart/wt before creating a cmux split so the
# child shell lands in the worktree instead of bouncing to main.
# _ZSHRC_LOADED: skip the guard on re-source (source ~/.zshrc from a worktree).
if [[ -n "$GX_WORKTREE_TARGET" ]]; then
  cd "$GX_WORKTREE_TARGET"
  unset GX_WORKTREE_TARGET
elif [[ "$PWD" == */worktrees/* && "$TERM_PROGRAM" != "vscode" && -z "$_ZSHRC_LOADED" ]]; then
  cd ~/Documents/dev/Quaestor-Web
fi
_ZSHRC_LOADED=1



# ─────────────────────────────────────────#
# FUNCTIONS                                #
# ─────────────────────────────────────────#

# Split right with retry; prints new surface ref. cmux can drop a split while
# the source pane is still settling.
function _gx_new_split {
  local _dir="$1" _surface="$2" _workspace="$3" _out _i
  for _i in 1 2 3; do
    _out=$(cmux new-split "$_dir" --surface "$_surface" --workspace "$_workspace" 2>/dev/null | grep -o 'surface:[0-9]*' | head -1)
    [[ -n "$_out" ]] && { print -r -- "$_out"; return 0; }
    sleep 0.3
  done
  return 1
}

# Shared by wt and gxstart: cd into worktree, label tab/workspace, build
# left | top-right (clients/web) / bottom-right (worktree root) layout.
function _gx_open_worktree {
  local target="$1"
  cd "$target" || return 1
  local _branch _label
  _branch="$(basename "$(dirname "$target")")/$(basename "$target")"
  _label="${_branch#feat/}"
  _label="${_label#fix/}"
  _label="${_label#spike/}"
  _label="🌿 $_label"
  ZSH_THEME_TERM_TITLE_IDLE="$_label"
  ZSH_THEME_TERM_TAB_TITLE_IDLE="$_label"
  local _identity _surface _workspace
  _identity=$(cmux identify 2>/dev/null)
  _surface=$(printf '%s' "$_identity" | grep -o 'surface:[0-9]*' | head -1)
  _workspace=$(printf '%s' "$_identity" | grep -o 'workspace:[0-9]*' | head -1)
  [[ -n "$_surface" ]] && cmux rename-tab --surface "$_surface" "$_label" 2>/dev/null || true
  [[ -n "$_workspace" ]] && cmux rename-workspace --workspace "$_workspace" "$_label" 2>/dev/null || true
  [[ -n "$_surface" && -n "$_workspace" ]] || return 0
  local _top_dir="$target"
  [[ -d "$target/clients/web" ]] && _top_dir="$target/clients/web"
  export GX_WORKTREE_TARGET="$target"
  local _top _bottom
  if _top=$(_gx_new_split right "$_surface" "$_workspace"); then
    cmux rename-tab --surface "$_top" "client" 2>/dev/null || true
    cmux send --surface "$_top" "cd $(printf '%q' "$_top_dir")" 2>/dev/null
    cmux send-key --surface "$_top" Return 2>/dev/null
    if _bottom=$(_gx_new_split down "$_top" "$_workspace"); then
      cmux send --surface "$_bottom" "cd $(printf '%q' "$target")" 2>/dev/null
      cmux send-key --surface "$_bottom" Return 2>/dev/null
    else
      echo "gx: bottom-right split failed" >&2
    fi
  else
    echo "gx: right split failed" >&2
  fi
  unset GX_WORKTREE_TARGET
}

function wt {
  local output
  output=$("$HOME/.dotfiles/.scripts/worktree" "$@") || return
  [[ -n "$output" ]] && _gx_open_worktree "$(printf '%s' "$output" | tail -1)"
}

function gxstart {
  local output
  output=$("$HOME/.dotfiles/.scripts/gxstart" "$@") || return
  [[ -n "$output" ]] && _gx_open_worktree "$(printf '%s' "$output" | tail -1)"
}

function gxlist {
  local _gl_is_filter=false
  for _gl_a in "$@"; do
    [[ "$_gl_a" == --* ]] && continue
    _gl_is_filter=true
    break
  done

  if [[ "$_gl_is_filter" == true ]]; then
    local _gl_branch
    _gl_branch=$("$HOME/.dotfiles/.scripts/gxlist" "$@")
    if [[ -n "$_gl_branch" ]]; then
      wt "$_gl_branch"
    fi
  else
    "$HOME/.dotfiles/.scripts/gxlist" "$@"
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

# Account Switchers (Using your fnm Node v24 global binary with isolated config directories)
alias cch="CLAUDE_CONFIG_DIR=\$HOME/.cch /Users/eric/.local/share/fnm/node-versions/v24.19.0/installation/bin/claude"
alias cco="CLAUDE_CONFIG_DIR=\$HOME/.cco /Users/eric/.local/share/fnm/node-versions/v24.19.0/installation/bin/claude"

# Diagnostics for each isolated environment
alias cch-doctor="CLAUDE_CONFIG_DIR=\$HOME/.cch /Users/eric/.local/share/fnm/node-versions/v24.19.0/installation/bin/claude doctor"
alias cco-doctor="CLAUDE_CONFIG_DIR=\$HOME/.cco /Users/eric/.local/share/fnm/node-versions/v24.19.0/installation/bin/claude doctor"

# Updaters (Since fnm handles the global binaries, this updates the actual package your aliases point to)
alias cc-update="npm install -g @anthropic-ai/claude-code@latest"
alias cch-update="cc-update"
alias cco-update="cc-update"

# Disable bare `claude` to avoid accidentally using the wrong account
alias claude="echo 'Use cco (office) or cch (home). Update: cc-update'"




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
[[ -f ~/.dotfiles/claude-code-shared/scripts/usage/cc-usage-nudge.sh ]] && \
  source ~/.dotfiles/claude-code-shared/scripts/usage/cc-usage-nudge.sh


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

