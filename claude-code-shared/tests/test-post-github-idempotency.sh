#!/usr/bin/env bash
# test-post-github-idempotency.sh
#
# Unit tests for the idempotency check pattern described in post-github.md.
# Stubs `gh api` to simulate:
#   (a) zero existing replies → expect exactly one POST call
#   (b) one existing reply   → expect zero POST calls
#
# Exit 0 = all tests passed. Exit 1 = one or more tests failed.

set -euo pipefail

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass() { echo "PASS: $1"; ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

# Run the idempotency check logic extracted from post-github.md step 3.
# Arguments:
#   $1 — thread_database_id (numeric)
#   $2 — mock_existing_count (number of existing replies the stub returns)
# Returns exit 0 (should post) or exit 1 (already posted, skip).
run_idempotency_check() {
  local thread_database_id="$1"
  local mock_existing_count="$2"

  # Stub out `gh` for this function's execution via a local PATH override.
  local stub_dir
  stub_dir=$(mktemp -d)
  trap "rm -rf '${stub_dir}'" RETURN

  local my_login="testuser"

  # Write the gh stub
  cat > "${stub_dir}/gh" <<STUB
#!/usr/bin/env bash
# Minimal gh api stub for idempotency tests.
# Handles:
#   gh api /user --jq '.login'
#   gh api "/repos/.../pulls/.../comments" --jq "... select(.in_reply_to_id == <N> ...) | length"
if [[ "\$1" == "api" && "\$2" == "/user" ]]; then
  echo "${my_login}"
  exit 0
fi
# For the comments check, return the mocked count
echo "${mock_existing_count}"
exit 0
STUB
  chmod +x "${stub_dir}/gh"

  # Idempotency logic (mirrors post-github.md step 3)
  # -------------------------------------------------------
  local owner="testowner"
  local repo="testrepo"
  local pr_number="42"

  local existing
  existing=$(PATH="${stub_dir}:${PATH}" gh api \
    "/repos/${owner}/${repo}/pulls/${pr_number}/comments" \
    --jq "[.[] | select(.in_reply_to_id == ${thread_database_id} and .user.login == \"${my_login}\")] | length" \
    2>/dev/null || echo "0")

  if [ "${existing:-0}" -gt 0 ]; then
    # Already posted — skip
    return 1
  fi
  # Not yet posted — proceed
  return 0
}

# Run an end-to-end stub simulating a full post-github.md scenario.
# Returns the number of POST calls made.
run_post_scenario() {
  local mock_existing_count="$1"
  local thread_database_id="22222"

  local stub_dir
  stub_dir=$(mktemp -d)
  trap "rm -rf '${stub_dir}'" RETURN

  local post_count_file="${stub_dir}/post_count"
  echo 0 > "${post_count_file}"

  local my_login="testuser"
  local owner="testowner"
  local repo="testrepo"
  local pr_number="42"

  # Write the gh stub
  cat > "${stub_dir}/gh" <<STUB
#!/usr/bin/env bash
# Count POST calls for end-to-end test
if [[ "\$1" == "api" && "\$2" == "/user" ]]; then
  echo "${my_login}"
  exit 0
fi
# All other calls: if --method POST, count it
for arg in "\$@"; do
  if [[ "\$arg" == "POST" ]]; then
    count=\$(cat "${post_count_file}")
    echo \$((count + 1)) > "${post_count_file}"
    # Return a minimal valid response
    echo '{"html_url":"https://github.com/testowner/testrepo/pull/42#issuecomment-99999"}'
    exit 0
  fi
done
# GET/list call — return mocked existing count
echo "${mock_existing_count}"
exit 0
STUB
  chmod +x "${stub_dir}/gh"

  # -- Idempotency check (step 3 of post-github.md) --
  local existing
  existing=$(PATH="${stub_dir}:${PATH}" gh api \
    "/repos/${owner}/${repo}/pulls/${pr_number}/comments" \
    --jq "[.[] | select(.in_reply_to_id == ${thread_database_id} and .user.login == \"${my_login}\")] | length" \
    2>/dev/null || echo "0")

  if [ "${existing:-0}" -gt 0 ]; then
    # Already posted — exit without POSTing (idempotency guard fires)
    cat "${post_count_file}"
    return 0
  fi

  # -- POST (step 4 of post-github.md) --
  local combined_draft="Test reply body"
  PATH="${stub_dir}:${PATH}" gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    "/repos/${owner}/${repo}/pulls/${pr_number}/comments" \
    -f body="${combined_draft}" \
    -F in_reply_to="${thread_database_id}" > /dev/null 2>&1
  local exit_code=$?

  # After the first POST returns, exit immediately.
  # Do not make a second POST call for any reason, including ambiguous response or missing html_url.
  cat "${post_count_file}"
}

# ---------------------------------------------------------------------------
# Test A — zero existing replies → idempotency check passes → POST should proceed
# ---------------------------------------------------------------------------
if run_idempotency_check "11111" "0"; then
  pass "A: zero existing replies — idempotency check passes (should post)"
else
  fail "A: zero existing replies — idempotency check should NOT block posting"
fi

# ---------------------------------------------------------------------------
# Test B — one existing reply → idempotency check fires → no POST
# ---------------------------------------------------------------------------
if run_idempotency_check "11111" "1"; then
  fail "B: one existing reply — idempotency check should have blocked posting"
else
  pass "B: one existing reply — idempotency check correctly blocks posting"
fi

# ---------------------------------------------------------------------------
# Test C — end-to-end: zero existing → exactly one POST made
# ---------------------------------------------------------------------------
post_count=$(run_post_scenario "0")
if [ "${post_count}" -eq 1 ]; then
  pass "C: zero existing replies → exactly 1 POST made"
else
  fail "C: zero existing replies → expected 1 POST, got ${post_count}"
fi

# ---------------------------------------------------------------------------
# Test D — end-to-end: one existing → zero POSTs made
# ---------------------------------------------------------------------------
post_count=$(run_post_scenario "1")
if [ "${post_count}" -eq 0 ]; then
  pass "D: one existing reply → 0 POSTs made (idempotency guard)"
else
  fail "D: one existing reply → expected 0 POSTs, got ${post_count}"
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
exit 0
