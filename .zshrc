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



# ─────────────────────────────────────────#
# ALIASES                                  #
# ─────────────────────────────────────────#

alias reload="source ~/.zshrc"
alias ls='eza --color=always --icons'
alias runcelery="celery -A task.celery worker --loglevel=info -Q user_waiting,notifications,integrations,longtasks,whenever,celery,email_parsing,doc_parsing"


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



# ─────────────────────────────────────────#
# FUNCTIONS                                #
# ─────────────────────────────────────────#

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

# Disable bare `claude` to avoid accidentally using the wrong account
alias claude="echo 'Use cco (office) or cch (home). Update: cch-update / cco-update'"



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



# ─────────────────────────────────────────#
# MACHINE-LOCAL OVERRIDES                  #
# ─────────────────────────────────────────#
# Gitignored — see local/zshrc.local.template

[[ -f ~/.dotfiles/local/zshrc.local ]] && source ~/.dotfiles/local/zshrc.local
