#!/usr/bin/env bash
# gx-lib.sh — shared helpers for the gx git toolkit

GX_POLICY_FILE="${GX_POLICY_FILE:-$HOME/.dotfiles/claude-code-shared/resources/repo-policy.json}"

# Normalize a git remote URL to "Org/Repo" form.
# Handles both ssh (git@github.com:Org/Repo.git) and https (https://github.com/Org/Repo.git).
gx_normalize_url() {
  local url="$1"
  # Strip trailing .git and trailing slashes
  url="${url%.git}"
  url="${url%/}"
  # SSH format: git@host:org/repo -> org/repo
  if [[ "$url" == *@*:* ]]; then
    url="${url##*:}"
  # HTTPS/HTTP format: https://host/org/repo -> org/repo
  elif [[ "$url" == https://* ]] || [[ "$url" == http://* ]]; then
    url="${url#*://}"     # strip protocol: //host/org/repo
    url="${url#*/}"       # strip host: org/repo
  fi
  echo "$url"
}

# Map account shorthand to CLAUDE_CONFIG_DIR path.
# "cco" -> ~/.cco (work), "cch" -> ~/.cch (home). Default: ~/.cch (safe for personal repos).
_gx_account_to_config() {
  case "$1" in
    cco) echo "$HOME/.cco" ;;
    cch) echo "$HOME/.cch" ;;
    *)   echo "$HOME/.cch" ;;
  esac
}

# Look up the policy entry for the current repo.
# Sets GX_LABEL, GX_BASE_BRANCH, GX_EXCLUDE_JSON, GX_CLAUDE_CONFIG in the caller's environment.
# Returns 0 on registered hit, 1 on unregistered fallback (with stderr warning).
gx_load_policy() {
  local remote_url key
  remote_url=$(git remote get-url origin 2>/dev/null)
  if [[ -z "$remote_url" ]]; then
    echo "gx-lib: no git remote 'origin' found — using conservative defaults" >&2
    GX_LABEL="unknown"
    GX_BASE_BRANCH="${GX_BASE_BRANCH:-main}"
    GX_EXCLUDE_JSON="[]"
    GX_CLAUDE_CONFIG="$(_gx_account_to_config cch)"
    return 1
  fi

  key=$(gx_normalize_url "$remote_url")

  if [[ ! -f "$GX_POLICY_FILE" ]]; then
    echo "gx-lib: policy file not found at $GX_POLICY_FILE — using conservative defaults" >&2
    GX_LABEL="unknown"
    GX_BASE_BRANCH="${GX_BASE_BRANCH:-main}"
    GX_EXCLUDE_JSON="[]"
    GX_CLAUDE_CONFIG="$(_gx_account_to_config cch)"
    return 1
  fi

  local entry
  entry=$(python3 -c "
import json, sys
with open('$GX_POLICY_FILE') as f:
    data = json.load(f)
key = '$key'
if key in data:
    e = data[key]
    print(e.get('label', 'unknown'))
    print(e.get('base_branch', 'main'))
    print(json.dumps(e.get('exclude', [])))
    print(e.get('account', 'cch'))
    print('true' if e.get('pr_draft', False) else 'false')
else:
    sys.exit(1)
" 2>/dev/null)

  if [[ $? -ne 0 ]]; then
    echo "gx-lib: repo '$key' not in policy registry — using conservative defaults" >&2
    GX_LABEL="unknown"
    GX_BASE_BRANCH="${GX_BASE_BRANCH:-main}"
    GX_EXCLUDE_JSON="[]"
    GX_CLAUDE_CONFIG="$(_gx_account_to_config cch)"
    return 1
  fi

  GX_LABEL=$(echo "$entry" | sed -n '1p')
  # Respect GX_BASE_BRANCH if already set in env (allows tests to inject a value)
  GX_BASE_BRANCH="${GX_BASE_BRANCH:-$(echo "$entry" | sed -n '2p')}"
  GX_EXCLUDE_JSON=$(echo "$entry" | sed -n '3p')
  GX_CLAUDE_CONFIG="$(_gx_account_to_config "$(echo "$entry" | sed -n '4p')")"
  GX_PR_DRAFT=$(echo "$entry" | sed -n '5p')
  return 0
}

# Return exclude patterns as a newline-separated list (for use with grep/find).
gx_exclude_patterns() {
  echo "$GX_EXCLUDE_JSON" | python3 -c "
import json, sys
patterns = json.load(sys.stdin)
for p in patterns:
    print(p)
"
}
