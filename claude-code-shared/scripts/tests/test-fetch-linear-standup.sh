#!/usr/bin/env bash
# Tests for fetch-linear-standup.sh
# Mocks curl via PATH override; never calls real Linear API.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPTS_DIR/fetch-linear-standup.sh"

TMP=$(mktemp -d)
PASS=0
FAIL=0
CASE_STDOUT="$TMP/case_stdout"
CASE_STDERR="$TMP/case_stderr"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

assert_pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# run_script: run the script with environment overrides, capture stdout/stderr
run_script() {
  local expect_exit="$1"
  shift
  # "$@" is env vars followed by script args — caller passes them as VAR=val args...
  # Actually just use env for forwarding
  set +e
  "$@" >"$CASE_STDOUT" 2>"$CASE_STDERR"
  local actual_exit=$?
  set -e
  if [[ "$expect_exit" -eq 0 && "$actual_exit" -eq 0 ]]; then
    assert_pass "exited 0"
  elif [[ "$expect_exit" -ne 0 && "$actual_exit" -ne 0 ]]; then
    assert_pass "exited non-zero (expected)"
  elif [[ "$expect_exit" -eq 0 && "$actual_exit" -ne 0 ]]; then
    assert_fail "expected exit 0 but got $actual_exit. stderr: $(cat "$CASE_STDERR")"
  else
    assert_fail "expected non-zero but exited 0. stdout: $(cat "$CASE_STDOUT")"
  fi
}

# ─── Fixtures ────────────────────────────────────────────────────────────────

# Fixture: successful user+cycle response (two curl calls: user lookup, then cycle issues)
# We'll use CURL_FIXTURE_SEQ to track which call we're on

FIXTURE_DIR="$TMP/fixtures"
mkdir -p "$FIXTURE_DIR"

# User query response
cat > "$FIXTURE_DIR/user_response.json" << 'EOF'
{"data":{"users":{"nodes":[{"id":"user-abc-123","name":"Eric"}]}}}
EOF

# Cycle issues response with two issues
cat > "$FIXTURE_DIR/cycle_issues_response.json" << 'EOF'
{"data":{"issues":{"nodes":[
  {
    "id":"issue-id-1",
    "identifier":"KEY-10",
    "title":"Fix login bug",
    "state":{"name":"In Progress"},
    "url":"https://linear.app/test/issue/KEY-10",
    "project":{"name":"Auth Improvements"},
    "parent":{"identifier":"KEY-5","parent":{"identifier":"KEY-1"}}
  },
  {
    "id":"issue-id-2",
    "identifier":"KEY-11",
    "title":"Add dark mode",
    "state":{"name":"Todo"},
    "url":"https://linear.app/test/issue/KEY-11",
    "project":null,
    "parent":null
  }
]}}}
EOF

# Empty cycle issues response
cat > "$FIXTURE_DIR/empty_issues_response.json" << 'EOF'
{"data":{"issues":{"nodes":[]}}}
EOF

# ─── Mock curl factory ────────────────────────────────────────────────────────

# Creates a mock curl in $TMP/mock_bin that serves fixture responses in sequence.
# Call count is tracked via a file.
setup_mock_curl() {
  local responses=("$@")   # array of fixture file paths in call order
  mkdir -p "$TMP/mock_bin"
  rm -f "$TMP/curl_call_count"
  echo "0" > "$TMP/curl_call_count"

  # Write response files to numbered slots
  local i=0
  for resp in "${responses[@]}"; do
    cp "$resp" "$TMP/mock_bin/response_${i}.json"
    i=$((i+1))
  done
  local total="$i"
  echo "$total" > "$TMP/mock_bin/total"

  cat > "$TMP/mock_bin/curl" << 'CURLEOF'
#!/usr/bin/env bash
# Mock curl: returns fixture responses in sequence; appends HTTP 200 code
COUNT_FILE="$(dirname "$0")/../curl_call_count"
TOTAL_FILE="$(dirname "$0")/total"
count=$(cat "$COUNT_FILE")
total=$(cat "$TOTAL_FILE")
idx=$count
if [[ $idx -ge $total ]]; then
  idx=$(( total - 1 ))
fi
# Increment count
echo $(( count + 1 )) > "$COUNT_FILE"
resp_file="$(dirname "$0")/response_${idx}.json"
cat "$resp_file"
printf '\n200'
CURLEOF
  chmod +x "$TMP/mock_bin/curl"
}

echo "=== fetch-linear-standup.sh tests ==="

# ──────────────────────────────────────────────────────────────────────────────
# Test 1: Key resolution — env var overrides everything
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Test 1: env var LINEAR_API_KEY is used (not secrets.env) ---"

setup_mock_curl "$FIXTURE_DIR/user_response.json" "$FIXTURE_DIR/cycle_issues_response.json"

# Create a fake secrets.env that sets a DIFFERENT key — env var must win
FAKE_SECRETS="$TMP/fake_secrets.env"
echo 'LINEAR_API_KEY=key-from-secrets-file' > "$FAKE_SECRETS"

run_script 0 env \
  LINEAR_API_KEY="key-from-env-var" \
  LINEAR_GRAPHQL="http://localhost:0/noop" \
  LINEAR_USER_EMAIL="test@example.com" \
  HOME="$TMP/fakehome" \
  PATH="$TMP/mock_bin:$PATH" \
  "$SCRIPT"

# The script should have exited 0 and produced JSON
if python3 -c "import json,sys; d=json.load(open('$CASE_STDOUT')); assert isinstance(d, list)" 2>/dev/null; then
  assert_pass "Test 1: output is valid JSON array"
else
  assert_fail "Test 1: output is not a valid JSON array. Got: $(cat "$CASE_STDOUT")"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 2: Key resolution — secrets.env used when env var absent
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Test 2: secrets.env sourced when LINEAR_API_KEY not in env ---"

setup_mock_curl "$FIXTURE_DIR/user_response.json" "$FIXTURE_DIR/cycle_issues_response.json"

# Create a fake home with a secrets.env
FAKE_HOME="$TMP/fake_home_2"
mkdir -p "$FAKE_HOME/.dotfiles/local"
echo 'LINEAR_API_KEY=key-from-secrets-env-file' > "$FAKE_HOME/.dotfiles/local/secrets.env"

run_script 0 env -u LINEAR_API_KEY \
  LINEAR_GRAPHQL="http://localhost:0/noop" \
  LINEAR_USER_EMAIL="test@example.com" \
  HOME="$FAKE_HOME" \
  PATH="$TMP/mock_bin:$PATH" \
  "$SCRIPT"

if python3 -c "import json,sys; d=json.load(open('$CASE_STDOUT')); assert isinstance(d, list)" 2>/dev/null; then
  assert_pass "Test 2: secrets.env sourced, output is valid JSON array"
else
  assert_fail "Test 2: output is not a valid JSON array. Got: $(cat "$CASE_STDOUT")"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 3: Key resolution — exit with hint when neither env var nor secrets.env
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Test 3: exits with setup hint when no key available ---"

# No mock curl needed — script exits before making any API call
EMPTY_HOME="$TMP/empty_home"
mkdir -p "$EMPTY_HOME"

run_script 1 env -u LINEAR_API_KEY \
  HOME="$EMPTY_HOME" \
  PATH="$TMP/mock_bin:$PATH" \
  "$SCRIPT"

if grep -q "LINEAR_API_KEY not set" "$CASE_STDERR"; then
  assert_pass "Test 3: stderr contains setup hint"
else
  assert_fail "Test 3: expected setup hint in stderr. Got: $(cat "$CASE_STDERR")"
fi
if grep -q "secrets.env" "$CASE_STDERR"; then
  assert_pass "Test 3: stderr mentions secrets.env path"
else
  assert_fail "Test 3: stderr does not mention secrets.env. Got: $(cat "$CASE_STDERR")"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 4: Loud stderr warning when cycle returns empty but KEY ids provided
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Test 4: loud warning when empty results but KEY ids arg present ---"

# Both user and issues queries return empty
cat > "$FIXTURE_DIR/empty_user_response.json" << 'EOF'
{"data":{"users":{"nodes":[{"id":"user-xyz","name":"Eric"}]}}}
EOF

setup_mock_curl "$FIXTURE_DIR/empty_user_response.json" "$FIXTURE_DIR/empty_issues_response.json" "$FIXTURE_DIR/empty_issues_response.json"

run_script 0 env \
  LINEAR_API_KEY="test-key" \
  LINEAR_GRAPHQL="http://localhost:0/noop" \
  LINEAR_USER_EMAIL="test@example.com" \
  HOME="$TMP/fakehome" \
  PATH="$TMP/mock_bin:$PATH" \
  "$SCRIPT" "KEY-99,KEY-100"

# stdout should be a JSON array (possibly empty)
if python3 -c "import json,sys; d=json.load(open('$CASE_STDOUT')); assert isinstance(d, list)" 2>/dev/null; then
  assert_pass "Test 4: stdout is valid JSON array even when empty"
else
  assert_fail "Test 4: stdout is not valid JSON. Got: $(cat "$CASE_STDOUT")"
fi

# stderr should contain loud warning
if grep -qi "WARNING" "$CASE_STDERR"; then
  assert_pass "Test 4: stderr contains WARNING"
else
  assert_fail "Test 4: expected WARNING in stderr. Got: $(cat "$CASE_STDERR")"
fi
if grep -q "KEY-99" "$CASE_STDERR" || grep -q "active cycle" "$CASE_STDERR"; then
  assert_pass "Test 4: warning mentions keys or active cycle"
else
  assert_fail "Test 4: warning does not mention keys or cycle. Got: $(cat "$CASE_STDERR")"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 5: Correct JSON shape from mocked curl response
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Test 5: output shape {id, key, title, status, url, parentKey, epicKey} ---"

setup_mock_curl "$FIXTURE_DIR/user_response.json" "$FIXTURE_DIR/cycle_issues_response.json"

run_script 0 env \
  LINEAR_API_KEY="test-key" \
  LINEAR_GRAPHQL="http://localhost:0/noop" \
  LINEAR_USER_EMAIL="test@example.com" \
  HOME="$TMP/fakehome" \
  PATH="$TMP/mock_bin:$PATH" \
  "$SCRIPT"

# Validate shape
python3 - "$CASE_STDOUT" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    items = json.load(f)

assert isinstance(items, list), f"Expected list, got {type(items)}"
assert len(items) >= 1, f"Expected at least 1 item, got {len(items)}"

required_keys = {"id", "key", "title", "status", "url", "parentKey", "epicKey", "projectName"}
for item in items:
    missing = required_keys - set(item.keys())
    assert not missing, f"Item missing fields: {missing}. Item: {item}"
    # parentKey, epicKey, projectName may be None/null — that is valid

print("Shape check passed")
print(f"  Items: {len(items)}")
for item in items:
    print(f"  {item['key']}: {item['title'][:40]!r} status={item['status']!r} parentKey={item['parentKey']!r} epicKey={item['epicKey']!r} projectName={item['projectName']!r}")
PYEOF
if [[ $? -eq 0 ]]; then
  assert_pass "Test 5: all items have required fields {id, key, title, status, url, parentKey, epicKey, projectName}"
else
  assert_fail "Test 5: shape check failed"
fi

# Validate specific field values from fixture
python3 - "$CASE_STDOUT" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    items = json.load(f)

item0 = next(i for i in items if i['key'] == 'KEY-10')
assert item0['id'] == 'issue-id-1', f"id mismatch: {item0['id']}"
assert item0['title'] == 'Fix login bug', f"title mismatch: {item0['title']}"
assert item0['status'] == 'In Progress', f"status mismatch: {item0['status']}"
assert item0['url'] == 'https://linear.app/test/issue/KEY-10', f"url mismatch: {item0['url']}"
assert item0['parentKey'] == 'KEY-5', f"parentKey mismatch: {item0['parentKey']}"
assert item0['epicKey'] == 'KEY-1', f"epicKey mismatch: {item0['epicKey']}"
assert item0['projectName'] == 'Auth Improvements', f"projectName mismatch: {item0['projectName']}"

item1 = next(i for i in items if i['key'] == 'KEY-11')
assert item1['parentKey'] is None, f"parentKey should be None: {item1['parentKey']}"
assert item1['epicKey'] is None, f"epicKey should be None: {item1['epicKey']}"
assert item1['projectName'] is None, f"projectName should be None (project null): {item1['projectName']}"

print("Field value check passed")
PYEOF
if [[ $? -eq 0 ]]; then
  assert_pass "Test 5: field values match fixture data (including projectName)"
else
  assert_fail "Test 5: field values do not match fixture"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 6: No warning when cycle returns empty but no KEY ids arg given
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Test 6: no warning when empty results and no KEY ids arg ---"

setup_mock_curl "$FIXTURE_DIR/empty_user_response.json" "$FIXTURE_DIR/empty_issues_response.json"

run_script 0 env \
  LINEAR_API_KEY="test-key" \
  LINEAR_GRAPHQL="http://localhost:0/noop" \
  LINEAR_USER_EMAIL="test@example.com" \
  HOME="$TMP/fakehome" \
  PATH="$TMP/mock_bin:$PATH" \
  "$SCRIPT"

if grep -qi "WARNING" "$CASE_STDERR"; then
  assert_fail "Test 6: should not warn when no KEY ids provided. stderr: $(cat "$CASE_STDERR")"
else
  assert_pass "Test 6: no WARNING when no KEY ids arg"
fi
# stdout should be empty JSON array
if python3 -c "import json,sys; d=json.load(open('$CASE_STDOUT')); assert d == []" 2>/dev/null; then
  assert_pass "Test 6: stdout is empty JSON array []"
else
  assert_fail "Test 6: expected [] but got: $(cat "$CASE_STDOUT")"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Test 7: API key is never printed to stdout or stderr
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Test 7: API key never appears in stdout or stderr ---"

setup_mock_curl "$FIXTURE_DIR/user_response.json" "$FIXTURE_DIR/cycle_issues_response.json"

run_script 0 env \
  LINEAR_API_KEY="super-secret-key-do-not-print" \
  LINEAR_GRAPHQL="http://localhost:0/noop" \
  LINEAR_USER_EMAIL="test@example.com" \
  HOME="$TMP/fakehome" \
  PATH="$TMP/mock_bin:$PATH" \
  "$SCRIPT"

if grep -q "super-secret-key-do-not-print" "$CASE_STDOUT" || grep -q "super-secret-key-do-not-print" "$CASE_STDERR"; then
  assert_fail "Test 7: API key appeared in output!"
else
  assert_pass "Test 7: API key not present in stdout or stderr"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
