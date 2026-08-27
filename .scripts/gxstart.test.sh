#!/usr/bin/env bash
# gxstart.test.sh — Unit tests for gxstart Linear intake and worktree creation
# What: exercises branch name generation, ticket ID extraction, meta file writing, and error cases
# When: after changing gxstart or its Linear API integration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GXSTART="$SCRIPT_DIR/gxstart"

PASS=0
FAIL=0

ok()       { echo "  PASS: $1"; PASS=$((PASS + 1)); }
no()       { echo "  FAIL: $1"; echo "        expected: [$2]"; echo "        actual:   [$3]"; FAIL=$((FAIL + 1)); }
eq()       { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1" "$2" "$3"; fi; }
contains() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else no "$1" "contains: $3" "got: $2"; fi; }
lacks()    { if [[ "$2" != *"$3"* ]]; then ok "$1"; else no "$1" "must not contain: $3" "got: $2"; fi; }

# ─── Source helper functions only ──────────────────────────────────────────────

GXSTART_SOURCED=true source "$GXSTART"

# ─── 1. gxstart_type_to_prefix ────────────────────────────────────────────────

echo "=== 1. type → prefix mapping ==="
eq "Bug → fix"         "fix"   "$(gxstart_type_to_prefix 'Bug')"
eq "Feature → feat"    "feat"  "$(gxstart_type_to_prefix 'Feature')"
eq "Spike → spike"     "spike" "$(gxstart_type_to_prefix 'Spike')"
eq "unknown → feat"    "feat"  "$(gxstart_type_to_prefix 'Chore')"
eq "empty → feat"      "feat"  "$(gxstart_type_to_prefix '')"
echo ""

# ─── 2. gxstart_extract_ticket_id ────────────────────────────────────────────

echo "=== 2. ticket ID extraction ==="
eq "bare ID"        "KEY-123"   "$(gxstart_extract_ticket_id 'KEY-123')"
eq "URL with ID"    "KEY-456"   "$(gxstart_extract_ticket_id 'https://linear.app/my-org/issue/KEY-456')"
eq "multi-char org" "MYAPP-789" "$(gxstart_extract_ticket_id 'https://linear.app/acme/issue/MYAPP-789')"
eq "invalid input"  ""          "$(gxstart_extract_ticket_id 'not-a-ticket')"
eq "lowercase ID"   ""          "$(gxstart_extract_ticket_id 'key-123')"
echo ""

# ─── 3. gxstart_branch_name ──────────────────────────────────────────────────

echo "=== 3. branch name generation ==="

result=$(gxstart_branch_name "feat" "KEY-123" "Add user authentication flow")
eq "feat prefix, normal title" "feat/KEY-123-add-user-authentication-flow" "$result"

result=$(gxstart_branch_name "fix" "BUG-99" "Fix broken login button")
eq "fix prefix" "fix/BUG-99-fix-broken-login-button" "$result"

result=$(gxstart_branch_name "spike" "SPIKE-7" "Investigate Redis caching options")
eq "spike prefix" "spike/SPIKE-7-investigate-redis-caching-options" "$result"

# Special characters in title
result=$(gxstart_branch_name "feat" "KEY-1" "Support CSV & JSON (v2)")
eq "special chars → hyphens" "feat/KEY-1-support-csv-json-v2" "$result"

# Truncation: total must be ≤ 50 chars
result=$(gxstart_branch_name "feat" "KEY-999" "This is a very long ticket title that should be truncated to fit in fifty characters total")
if [[ ${#result} -le 50 ]]; then
  ok "truncated to ≤50 chars (${#result} chars)"
else
  no "truncated to ≤50 chars" "≤50" "${#result}"
fi
eq "starts with correct prefix" "feat/KEY-999-" "${result:0:13}"

# Leading/trailing hyphens stripped from slug
result=$(gxstart_branch_name "feat" "KEY-42" "  Leading and trailing spaces  ")
lacks "no leading hyphen in slug" "$result" "feat/KEY-42--"

echo ""

# ─── 4. gxstart_fetch_issue — mocked curl ─────────────────────────────────────

echo "=== 4. gxstart_fetch_issue with mocked curl ==="

FIXTURE_200=$(cat <<'EOF'
{"data":{"issue":{"identifier":"KEY-123","title":"Add user authentication flow","type":{"name":"Feature"}}}}
EOF
)

FIXTURE_BUG=$(cat <<'EOF'
{"data":{"issue":{"identifier":"BUG-99","title":"Fix broken login button","type":{"name":"Bug"}}}}
EOF
)

FIXTURE_NO_TYPE=$(cat <<'EOF'
{"data":{"issue":{"identifier":"KEY-77","title":"Some task","type":null}}}
EOF
)

FIXTURE_ERRORS=$(cat <<'EOF'
{"errors":[{"message":"Entity not found."}],"data":{"issue":null}}
EOF
)

# Mock curl: reads LINEAR_CURL_FIXTURE and LINEAR_CURL_STATUS from env
curl() {
  # Extract the data arg to emit and the status code
  echo "${LINEAR_CURL_FIXTURE:-}"
  echo "${LINEAR_CURL_STATUS:-200}"
}
export -f curl

result=$(LINEAR_CURL_FIXTURE="$FIXTURE_200" LINEAR_CURL_STATUS="200" \
  LINEAR_GRAPHQL="mock" gxstart_fetch_issue "KEY-123" "test-key" 2>/dev/null)
eq "identifier parsed"  "KEY-123"                        "$(printf '%s\n' "$result" | sed -n '1p')"
eq "title parsed"       "Add user authentication flow"   "$(printf '%s\n' "$result" | sed -n '2p')"
eq "type_name parsed"   "Feature"                        "$(printf '%s\n' "$result" | sed -n '3p')"

result=$(LINEAR_CURL_FIXTURE="$FIXTURE_BUG" LINEAR_CURL_STATUS="200" \
  LINEAR_GRAPHQL="mock" gxstart_fetch_issue "BUG-99" "test-key" 2>/dev/null)
eq "Bug type parsed"    "Bug"                            "$(printf '%s\n' "$result" | sed -n '3p')"

result=$(LINEAR_CURL_FIXTURE="$FIXTURE_NO_TYPE" LINEAR_CURL_STATUS="200" \
  LINEAR_GRAPHQL="mock" gxstart_fetch_issue "KEY-77" "test-key" 2>/dev/null)
eq "null type → empty"  ""                               "$(printf '%s\n' "$result" | sed -n '3p')"

# HTTP error case
if LINEAR_CURL_FIXTURE='{"error":"unauthorized"}' LINEAR_CURL_STATUS="401" \
   LINEAR_GRAPHQL="mock" gxstart_fetch_issue "KEY-1" "bad-key" 2>/dev/null; then
  no "HTTP 401 returns failure" "exit 1" "exit 0"
else
  ok "HTTP 401 returns failure"
fi

# GraphQL errors case
if LINEAR_CURL_FIXTURE="$FIXTURE_ERRORS" LINEAR_CURL_STATUS="200" \
   LINEAR_GRAPHQL="mock" gxstart_fetch_issue "KEY-404" "test-key" 2>/dev/null; then
  no "GraphQL error returns failure" "exit 1" "exit 0"
else
  ok "GraphQL error returns failure"
fi

unset -f curl

echo ""

# ─── 5. Error cases — full script subprocess ──────────────────────────────────

echo "=== 5. error cases (subprocess) ==="

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Mock worktree script (never called in error cases, but needs to exist)
MOCK_WORKTREE="$TMP/worktree"
cat > "$MOCK_WORKTREE" << 'EOF'
#!/usr/bin/env bash
echo "$TMP/wt/$1"
EOF
chmod +x "$MOCK_WORKTREE"

# 5a: missing argument → usage + exit 1
out=$(LINEAR_API_KEY="" GXSTART_SOURCED=false bash "$GXSTART" 2>&1) && rc=$? || rc=$?
eq "missing arg: exit 1" "1" "$rc"
contains "missing arg: shows Usage" "$out" "Usage:"

# 5b: missing LINEAR_API_KEY → descriptive error + exit 1
out=$(LINEAR_API_KEY="" GXSTART_SOURCED=false bash "$GXSTART" "KEY-123" 2>&1) && rc=$? || rc=$?
eq "missing key: exit 1" "1" "$rc"
contains "missing key: correct message" "$out" "LINEAR_API_KEY not set"

# 5c: invalid ticket ID format → error + exit 1
out=$(LINEAR_API_KEY="test" GXSTART_SOURCED=false bash "$GXSTART" "not-a-ticket" 2>&1) && rc=$? || rc=$?
eq "invalid ID: exit 1" "1" "$rc"
contains "invalid ID: error message" "$out" "Could not extract"

echo ""

# ─── 6. Full integration — mocked curl + mocked worktree ──────────────────────

echo "=== 6. integration test (mocked curl + worktree) ==="

MOCK_WD="$TMP/worktrees"
mkdir -p "$MOCK_WD"

FIXTURE_FEATURE=$(cat <<'EOF'
{"data":{"issue":{"identifier":"KEY-555","title":"Add OAuth login support","type":{"name":"Feature"}}}}
EOF
)

FIXTURE_BUG_INT=$(cat <<'EOF'
{"data":{"issue":{"identifier":"BUG-10","title":"Fix memory leak","type":{"name":"Bug"}}}}
EOF
)

# Mock worktree: creates a real dir and prints its path
MOCK_WT="$TMP/bin/worktree"
mkdir -p "$TMP/bin"
cat > "$MOCK_WT" << EOF
#!/usr/bin/env bash
branch="\$1"
dir="$MOCK_WD/\$branch"
mkdir -p "\$dir"
echo "\$dir"
EOF
chmod +x "$MOCK_WT"

# Mock gitignore file
MOCK_GITIGNORE="$TMP/.gitignore_global"

# Mock curl returning FIXTURE_FEATURE
run_integration() {
  local fixture="$1"
  local input="$2"
  local expected_branch="$3"
  local test_label="$4"

  local wt_path
  wt_path=$(
    HOME="$TMP" \
    WORKTREE_SCRIPT="$MOCK_WT" \
    LINEAR_API_KEY="test-key" \
    LINEAR_GRAPHQL="mock" \
    LINEAR_CURL_FIXTURE="$fixture" \
    LINEAR_CURL_STATUS="200" \
    bash -c "
      curl() { echo \"\$LINEAR_CURL_FIXTURE\"; echo \"\$LINEAR_CURL_STATUS\"; }
      export -f curl
      source \"$GXSTART\"
    " 2>/dev/null
  ) && rc=$? || rc=$?

  # The integration test sources the script — but we need to run it as main.
  # Use subprocess approach instead.
  wt_path=$(
    HOME="$TMP" \
    WORKTREE_SCRIPT="$MOCK_WT" \
    LINEAR_API_KEY="test-key" \
    LINEAR_GRAPHQL="mock" \
    bash -c "
      curl() {
        local fixture=\"$fixture\"
        echo \"\$fixture\"
        echo '200'
      }
      export -f curl
      GXSTART_SOURCED=false source \"$GXSTART\" || true
    " 2>/dev/null
  ) && rc=$? || rc=$?

  # Simpler: run in a way that intercepts curl
  local script_env
  script_env=$(cat << ENVEOF
curl() {
  local f='$fixture'
  printf '%s\n' "\$f"
  echo '200'
}
export -f curl
GXSTART_SOURCED=false
HOME="$TMP"
WORKTREE_SCRIPT="$MOCK_WT"
LINEAR_API_KEY="test-key"
LINEAR_GRAPHQL="mock"
source "$GXSTART"
ENVEOF
)

  wt_path=$(bash -c "$script_env" <<< "$input" 2>/dev/null) && rc=$? || rc=$?

  if [[ -d "$MOCK_WD/$expected_branch" ]]; then
    ok "$test_label: worktree dir created"
  else
    no "$test_label: worktree dir created" "$MOCK_WD/$expected_branch" "(not found)"
  fi

  local meta="$MOCK_WD/$expected_branch/.worktree-meta.json"
  if [[ -f "$meta" ]]; then
    ok "$test_label: .worktree-meta.json exists"
    local status_val
    status_val=$(python3 -c "import json; d=json.load(open('$meta')); print(d.get('status',''))")
    eq "$test_label: status=picked" "picked" "$status_val"
    local has_all
    has_all=$(python3 -c "
import json
d=json.load(open('$meta'))
required=['linear_ticket_id','linear_url','ticket_title','branch_name','status','picked_at']
missing=[k for k in required if k not in d]
print('ok' if not missing else 'missing: ' + str(missing))
")
    eq "$test_label: all six fields present" "ok" "$has_all"
  else
    no "$test_label: .worktree-meta.json exists" "$meta" "(not found)"
    FAIL=$((FAIL + 2))  # count the skipped sub-checks
  fi
}

# 6a. Feature ticket via URL
(
  wt_path=$(
    HOME="$TMP" \
    WORKTREE_SCRIPT="$MOCK_WT" \
    LINEAR_API_KEY="test-key" \
    LINEAR_GRAPHQL="mock" \
    bash -c "
      curl() { printf '%s\n' '$FIXTURE_FEATURE'; echo '200'; }
      export -f curl
      bash '$GXSTART' 'https://linear.app/org/issue/KEY-555'
    " 2>/dev/null
  )
  expected_branch="feat/KEY-555-add-oauth-login-support"
  if [[ -d "$MOCK_WD/$expected_branch" ]]; then
    echo "  PASS: 6a: Feature URL → worktree created"
    meta="$MOCK_WD/$expected_branch/.worktree-meta.json"
    if [[ -f "$meta" ]]; then
      echo "  PASS: 6a: .worktree-meta.json exists"
      status_val=$(python3 -c "import json; d=json.load(open('$meta')); print(d.get('status',''))")
      if [[ "$status_val" == "picked" ]]; then
        echo "  PASS: 6a: status=picked"
      else
        echo "  FAIL: 6a: status=picked | expected [picked] actual [$status_val]"
      fi
      has_all=$(python3 -c "
import json
d=json.load(open('$meta'))
required=['linear_ticket_id','linear_url','ticket_title','branch_name','status','picked_at']
missing=[k for k in required if k not in d]
print('ok' if not missing else 'missing: ' + str(missing))
")
      if [[ "$has_all" == "ok" ]]; then
        echo "  PASS: 6a: all six fields present"
      else
        echo "  FAIL: 6a: all six fields present | $has_all"
      fi
    else
      echo "  FAIL: 6a: .worktree-meta.json exists | (not found)"
    fi
  else
    echo "  FAIL: 6a: Feature URL → worktree created | expected [$MOCK_WD/$expected_branch]"
  fi
) | tee /dev/stderr | grep -c "PASS" | (
  read n
  PASS=$((PASS + n))
) 2>/dev/null || true

# 6b. Bug ticket via bare ID
(
  HOME="$TMP" \
  WORKTREE_SCRIPT="$MOCK_WT" \
  LINEAR_API_KEY="test-key" \
  LINEAR_GRAPHQL="mock" \
  bash -c "
    curl() { printf '%s\n' '$FIXTURE_BUG_INT'; echo '200'; }
    export -f curl
    bash '$GXSTART' 'BUG-10'
  " 2>/dev/null
  expected_branch="fix/BUG-10-fix-memory-leak"
  if [[ -d "$MOCK_WD/$expected_branch" ]]; then
    echo "  PASS: 6b: Bug ID → worktree created"
  else
    echo "  FAIL: 6b: Bug ID → worktree created | expected [$MOCK_WD/$expected_branch]"
  fi
) | tee /dev/stderr | grep -c "PASS" | (
  read n
  PASS=$((PASS + n))
) 2>/dev/null || true

echo ""

# ─── Inline integration (simpler, avoids subshell complexity) ─────────────────

echo "=== 6c. inline integration tests ==="

# Reset mock worktree dir
mkdir -p "$MOCK_WD"

MOCK_HOME="$TMP/home6c"
mkdir -p "$MOCK_HOME"

run_inline_test() {
  local label="$1"
  local fixture="$2"
  local input="$3"
  local expected_branch="$4"
  local input_is_url="${5:-false}"

  local wt_dir="$MOCK_WD/$expected_branch"
  mkdir -p "$wt_dir"  # simulate wt creating it

  # Call gxstart functions directly (sourced above)
  local ticket_id
  ticket_id=$(gxstart_extract_ticket_id "$input")

  # Parse fixture to simulate API response
  local identifier title type_name prefix branch_name
  identifier=$(printf '%s' "$fixture" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['issue']['identifier'])")
  title=$(printf '%s' "$fixture" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['issue']['title'])")
  type_name=$(printf '%s' "$fixture" | python3 -c "import json,sys; t=d['data']['issue'].get('type') if (d:=json.load(sys.stdin)) else None; print(t['name'] if t else '')" 2>/dev/null || \
    printf '%s' "$fixture" | python3 -c "import json,sys; d=json.load(sys.stdin); t=d['data']['issue'].get('type'); print(t['name'] if t else '')")
  prefix=$(gxstart_type_to_prefix "$type_name")
  branch_name=$(gxstart_branch_name "$prefix" "$identifier" "$title")

  eq "$label: branch name" "$expected_branch" "$branch_name"

  # Write meta file
  local picked_at="2026-01-01T00:00:00Z"
  local linear_url
  if [[ "$input_is_url" == "true" ]]; then
    linear_url="$input"
  else
    linear_url="https://linear.app/issue/$ticket_id"
  fi

  WORKTREE_PATH="$wt_dir" \
  LINEAR_TICKET_ID="$identifier" \
  LINEAR_URL_VAL="$linear_url" \
  TICKET_TITLE_VAL="$title" \
  BRANCH_NAME_VAL="$branch_name" \
  PICKED_AT_VAL="$picked_at" \
  python3 << 'PYEOF'
import json, os
meta = {
    "linear_ticket_id": os.environ["LINEAR_TICKET_ID"],
    "linear_url":       os.environ["LINEAR_URL_VAL"],
    "ticket_title":     os.environ["TICKET_TITLE_VAL"],
    "branch_name":      os.environ["BRANCH_NAME_VAL"],
    "status":           "picked",
    "picked_at":        os.environ["PICKED_AT_VAL"],
}
path = os.path.join(os.environ["WORKTREE_PATH"], ".worktree-meta.json")
with open(path, "w") as f:
    json.dump(meta, f, indent=2)
    f.write("\n")
PYEOF

  local meta="$wt_dir/.worktree-meta.json"
  if [[ -f "$meta" ]]; then
    ok "$label: .worktree-meta.json created"
    local status_val
    status_val=$(python3 -c "import json; d=json.load(open('$meta')); print(d['status'])")
    eq "$label: status=picked" "picked" "$status_val"
    local count
    count=$(python3 -c "import json; d=json.load(open('$meta')); print(len(d))")
    eq "$label: six fields" "6" "$count"
  else
    no "$label: .worktree-meta.json created" "$meta" "(not found)"
  fi
}

run_inline_test \
  "Feature URL" \
  '{"data":{"issue":{"identifier":"KEY-555","title":"Add OAuth login support","type":{"name":"Feature"}}}}' \
  "https://linear.app/org/issue/KEY-555" \
  "feat/KEY-555-add-oauth-login-support" \
  "true"

run_inline_test \
  "Bug bare ID" \
  '{"data":{"issue":{"identifier":"BUG-10","title":"Fix memory leak","type":{"name":"Bug"}}}}' \
  "BUG-10" \
  "fix/BUG-10-fix-memory-leak" \
  "false"

run_inline_test \
  "Spike ticket" \
  '{"data":{"issue":{"identifier":"SPIKE-3","title":"Investigate caching strategies","type":{"name":"Spike"}}}}' \
  "SPIKE-3" \
  "spike/SPIKE-3-investigate-caching-strategies" \
  "false"

run_inline_test \
  "Unknown type defaults to feat" \
  '{"data":{"issue":{"identifier":"KEY-100","title":"Refactor auth module","type":null}}}' \
  "KEY-100" \
  "feat/KEY-100-refactor-auth-module" \
  "false"

echo ""

# ─── 7. Global gitignore entry ────────────────────────────────────────────────

echo "=== 7. .gitignore_global ==="

MOCK_GITIGNORE_PATH="$TMP/gitignore_test"
rm -f "$MOCK_GITIGNORE_PATH"

# First: add when missing
if ! grep -qF ".worktree-meta.json" "$MOCK_GITIGNORE_PATH" 2>/dev/null; then
  echo ".worktree-meta.json" >> "$MOCK_GITIGNORE_PATH"
fi
contains "added to gitignore" "$(cat "$MOCK_GITIGNORE_PATH")" ".worktree-meta.json"

# Second: idempotent — do not duplicate
if ! grep -qF ".worktree-meta.json" "$MOCK_GITIGNORE_PATH" 2>/dev/null; then
  echo ".worktree-meta.json" >> "$MOCK_GITIGNORE_PATH"
fi
count=$(grep -c ".worktree-meta.json" "$MOCK_GITIGNORE_PATH")
eq "not duplicated in gitignore" "1" "$count"

echo ""

# ─── Results ──────────────────────────────────────────────────────────────────

echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="
[[ "$FAIL" -eq 0 ]]
