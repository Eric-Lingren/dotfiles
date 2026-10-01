#!/usr/bin/env bash
# fetch-linear-standup.sh — fetch Linear tickets assigned to user in the active cycle
#
# Usage: fetch-linear-standup.sh [KEY-1,KEY-2,...]
#
# Optional positional arg: comma-separated list of KEY ids to include even if
# not returned by the assignee+cycle query.
#
# Key resolution order:
#   1. LINEAR_API_KEY env var (already set)
#   2. Source ~/.dotfiles/local/secrets.env
#   3. Exit with a setup hint
#
# Output: JSON array of {id, key, title, status, url, parentKey, epicKey} to stdout.
# Errors go to stderr. LINEAR_API_KEY is never printed or written.

set -euo pipefail

LINEAR_GRAPHQL="${LINEAR_GRAPHQL:-https://api.linear.app/graphql}"
LINEAR_USER_EMAIL="${LINEAR_USER_EMAIL:-eric@standardmetrics.io}"

# ─── Key resolution ───────────────────────────────────────────────────────────

_resolve_api_key() {
  if [[ -n "${LINEAR_API_KEY:-}" ]]; then
    return 0
  fi
  local secrets_file="$HOME/.dotfiles/local/secrets.env"
  if [[ -f "$secrets_file" ]]; then
    # shellcheck source=/dev/null
    source "$secrets_file"
  fi
  if [[ -z "${LINEAR_API_KEY:-}" ]]; then
    echo "LINEAR_API_KEY not set — add it to ~/.dotfiles/local/secrets.env" >&2
    exit 1
  fi
}

# ─── GraphQL helper ───────────────────────────────────────────────────────────

# _gql QUERY  →  prints JSON response body, exits non-zero on HTTP/API error
_gql() {
  local query="$1"
  local response http_body http_code
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: ${LINEAR_API_KEY}" \
    --data "$query" \
    "$LINEAR_GRAPHQL")
  http_body=$(printf '%s\n' "$response" | sed '$d')
  http_code=$(printf '%s\n' "$response" | tail -n 1)

  if [[ "$http_code" != "200" ]]; then
    echo "Linear API error (HTTP $http_code)" >&2
    printf '%s\n' "$http_body" >&2
    return 1
  fi

  local errors
  errors=$(printf '%s' "$http_body" | python3 -c "
import json, sys
d = json.load(sys.stdin)
errs = d.get('errors', [])
if errs:
    for e in errs:
        print(e.get('message', 'unknown error'), file=sys.stderr)
    sys.exit(1)
print(json.dumps(d.get('data', {})))
" 2>&1) || { echo "$errors" >&2; return 1; }
  printf '%s' "$errors"
}

# ─── Resolve user id by email ─────────────────────────────────────────────────

_resolve_user_id() {
  local email="$1"
  local query
  query=$(python3 -c "
import json
q = '{\"query\":\"{users(filter:{email:{eq:\\\"%s\\\"}}) {nodes{id name}}}\"}' % '$email'
print(q)
")
  local data
  data=$(_gql "$query")
  local user_id
  user_id=$(printf '%s' "$data" | python3 -c "
import json, sys
d = json.load(sys.stdin)
nodes = d.get('users', {}).get('nodes', [])
if not nodes:
    print('No user found for email $email', file=sys.stderr)
    sys.exit(1)
print(nodes[0]['id'])
")
  printf '%s' "$user_id"
}

# ─── Fetch issues in active cycle assigned to user ────────────────────────────

_fetch_cycle_issues() {
  local user_id="$1"
  local query
  query=$(python3 -c "
uid = '$user_id'
gql = '''
{
  issues(
    filter: {
      assignee: { id: { eq: \"%s\" } }
      cycle: { isActive: { eq: true } }
    }
    first: 50
  ) {
    nodes {
      id
      identifier
      title
      state { name }
      url
      parent {
        identifier
        parent { identifier }
      }
    }
  }
}
''' % uid
import json
print(json.dumps({'query': gql}))
")
  _gql "$query"
}

# ─── Fetch issues by KEY ids ──────────────────────────────────────────────────

_fetch_issues_by_keys() {
  local key_list="$1"   # comma-separated, e.g. "KEY-1,KEY-2"
  local query
  query=$(python3 -c "
keys = '$key_list'.split(',')
keys = [k.strip() for k in keys if k.strip()]
filter_parts = ' '.join('{identifier: {eq: \"%s\"}}' % k for k in keys)
if len(keys) == 1:
    filter_clause = '{identifier: {eq: \"%s\"}}' % keys[0]
else:
    filter_clause = '{or: [%s]}' % filter_parts
gql = '''
{
  issues(filter: %s first: 50) {
    nodes {
      id
      identifier
      title
      state { name }
      url
      parent {
        identifier
        parent { identifier }
      }
    }
  }
}
''' % filter_clause
import json
print(json.dumps({'query': gql}))
")
  _gql "$query"
}

# ─── Parse issues nodes into output objects ───────────────────────────────────

_parse_issues() {
  python3 -c "
import json, sys
data = json.load(sys.stdin)
nodes = data.get('issues', {}).get('nodes', [])
results = []
for n in nodes:
    parent = n.get('parent') or {}
    grandparent = parent.get('parent') or {}
    results.append({
        'id': n.get('id', ''),
        'key': n.get('identifier', ''),
        'title': n.get('title', ''),
        'status': (n.get('state') or {}).get('name', ''),
        'url': n.get('url', ''),
        'parentKey': parent.get('identifier') or None,
        'epicKey': grandparent.get('identifier') or None,
    })
json.dump(results, sys.stdout, indent=2)
print()
"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  local extra_keys="${1:-}"

  _resolve_api_key

  # Resolve user id
  local user_id
  user_id=$(_resolve_user_id "$LINEAR_USER_EMAIL")

  # Fetch cycle issues
  local cycle_data extra_data
  cycle_data=$(_fetch_cycle_issues "$user_id")

  # Parse cycle issues
  local cycle_issues
  cycle_issues=$(printf '%s' "$cycle_data" | _parse_issues)

  # Build set of keys already fetched
  local fetched_keys
  fetched_keys=$(printf '%s' "$cycle_issues" | python3 -c "
import json, sys
items = json.load(sys.stdin)
print(','.join(i['key'] for i in items if i.get('key')))
")

  # If extra keys specified, find which are missing
  local missing_keys=""
  if [[ -n "$extra_keys" ]]; then
    missing_keys=$(python3 -c "
provided = set(k.strip() for k in '$extra_keys'.split(',') if k.strip())
fetched = set(k.strip() for k in '$fetched_keys'.split(',') if k.strip())
missing = provided - fetched
print(','.join(sorted(missing)))
")
  fi

  # Fetch missing keys if any
  local extra_issues="[]"
  if [[ -n "$missing_keys" ]]; then
    extra_data=$(_fetch_issues_by_keys "$missing_keys")
    extra_issues=$(printf '%s' "$extra_data" | _parse_issues)
  fi

  # Merge cycle + extra issues (deduplicate by key)
  local merged
  merged=$(python3 -c "
import json, sys

cycle = json.loads('$cycle_issues' if '$cycle_issues' else '[]')
extra = json.loads('''$extra_issues''')

seen = set()
result = []
for item in cycle + extra:
    k = item.get('key')
    if k and k not in seen:
        seen.add(k)
        result.append(item)

json.dump(result, sys.stdout, indent=2)
print()
" 2>/dev/null) || {
    # Fallback for complex JSON — use temp files
    local tmp_cycle tmp_extra
    tmp_cycle=$(mktemp)
    tmp_extra=$(mktemp)
    printf '%s\n' "$cycle_issues" > "$tmp_cycle"
    printf '%s\n' "$extra_issues" > "$tmp_extra"
    merged=$(python3 - "$tmp_cycle" "$tmp_extra" <<'PYEOF'
import json, sys
cycle = json.load(open(sys.argv[1]))
extra = json.load(open(sys.argv[2]))
seen = set()
result = []
for item in cycle + extra:
    k = item.get('key')
    if k and k not in seen:
        seen.add(k)
        result.append(item)
json.dump(result, sys.stdout, indent=2)
print()
PYEOF
)
    rm -f "$tmp_cycle" "$tmp_extra"
  }

  # Warn loudly if no tickets found but KEY ids were specified
  local total_count
  total_count=$(printf '%s' "$merged" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
  if [[ "$total_count" -eq 0 ]] && [[ -n "$extra_keys" ]]; then
    echo "" >&2
    echo "WARNING: Linear returned no tickets for this user in the active cycle," >&2
    echo "         and the requested KEY ids ($extra_keys) were also not found." >&2
    echo "         The active cycle may be empty or the tickets may not be assigned to you." >&2
    echo "" >&2
  fi

  printf '%s\n' "$merged"
}

main "$@"
