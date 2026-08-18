#!/usr/bin/env bash
# gxpush-pr-desc.test.sh — Integration tests for gxpush's PR description backfill
# What: runs gxpush --push-only --auto against a throwaway repo with a stubbed gh and pr-desc,
#       asserting when it fills a PR body and when it leaves one alone
# When: after changing the PR description section of gxpush or gx-pr-body

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GXPUSH="$SCRIPT_DIR/gxpush"

PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
no() { echo "  FAIL: $1"; echo "        $2"; FAIL=$((FAIL + 1)); }
contains() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else no "$1" "missing [$3] in: $2"; fi; }
lacks() { if [[ "$2" != *"$3"* ]]; then ok "$1"; else no "$1" "unexpected [$3] in: $2"; fi; }

ROOT=$(mktemp -d)
trap 'chmod -R u+w "$ROOT" 2>/dev/null; rm -rf "$ROOT"' EXIT

# --- Stub pr-desc: deterministic body, no Claude call ---
STUB_DESC="$ROOT/stub-pr-desc"
cat > "$STUB_DESC" <<'EOF'
#!/usr/bin/env bash
echo "### Generated title"
echo ""
echo "Generated summary sentence."
EOF
chmod +x "$STUB_DESC"

# --- Stub gh: PR state driven by files, edits recorded ---
STUB_BIN="$ROOT/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
# Reads $GH_PR_BODY_FILE (absent = no PR). Records edits to $GH_EDIT_OUT.
case "$1 $2" in
  "pr view")
    [[ -f "$GH_PR_BODY_FILE" ]] || exit 1
    python3 -c '
import json, os, sys
body = open(os.environ["GH_PR_BODY_FILE"]).read()
print(json.dumps({"number": 4242, "url": "https://example.test/pr/4242", "body": body}))
'
    ;;
  "pr edit")
    for ((i = 1; i <= $#; i++)); do
      if [[ "${!i}" == "--body-file" ]]; then
        j=$((i + 1))
        cp "${!j}" "$GH_EDIT_OUT"
      fi
    done
    echo "https://example.test/pr/4242"
    ;;
  "pr create")
    for ((i = 1; i <= $#; i++)); do
      if [[ "${!i}" == "--body-file" ]]; then
        j=$((i + 1))
        cp "${!j}" "$GH_EDIT_OUT"
      fi
    done
    echo "https://example.test/pr/9999"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$STUB_BIN/gh"

# --- Throwaway repo with a bare origin and a PR template ---
REPO="$ROOT/repo"
ORIGIN="$ROOT/origin.git"
git init -q --bare "$ORIGIN"
git init -q -b main "$REPO"
mkdir -p "$REPO/.github"
cat > "$REPO/.github/pull_request_template.md" <<'TPL'
## Summary

Provide at least a 1-2 sentence summary of what this PR changes.

<details>
   <summary><b>Data model changes?</b></summary>

- [ ] I have made the appropriate anonymization changes.

</details>
TPL
(
  cd "$REPO"
  git config user.email t@t.test
  git config user.name Test
  git add -A
  git commit -qm "init"
  git remote add origin "$ORIGIN"
  git push -q -u origin main 2>/dev/null
  git checkout -qb feat/thing
  echo hi > file.txt
  git add -A
  git commit -qm "add file"
)

run_gxpush() {
  (
    cd "$REPO"
    PATH="$STUB_BIN:$PATH" \
    GX_PR_DESC_CMD="$STUB_DESC" \
    GH_PR_BODY_FILE="$ROOT/pr_body" \
    GH_EDIT_OUT="$ROOT/edited" \
    GX_POLICY_FILE="/nonexistent" \
      bash "$GXPUSH" --push-only --auto "$@" 2>&1
  )
}

reset_state() {
  rm -f "$ROOT/edited"
  if [[ -n "$1" ]]; then cp "$1" "$ROOT/pr_body"; else rm -f "$ROOT/pr_body"; fi
}

echo "=== gxpush PR description integration tests ==="
echo ""

echo "1. Existing PR with an unfilled template — backfills, keeps checklist"
reset_state "$REPO/.github/pull_request_template.md"
OUT=$(run_gxpush)
contains "reports unfilled template" "$OUT" "unfilled PR template"
contains "reports the update" "$OUT" "updated on PR #4242"
EDITED=$(cat "$ROOT/edited" 2>/dev/null)
contains "body gains generated title" "$EDITED" "### Generated title"
lacks "placeholder removed" "$EDITED" "Provide at least a 1-2 sentence summary"
contains "checklist survives" "$EDITED" "- [ ] I have made the appropriate anonymization changes."
contains "details block survives" "$EDITED" "</details>"
echo ""

echo "2. Existing PR with a real description — left alone"
printf '## Summary\n\nA human already wrote this properly.\n' > "$ROOT/human_body"
reset_state "$ROOT/human_body"
OUT=$(run_gxpush)
contains "reports already written" "$OUT" "already written"
contains "says leaving as-is" "$OUT" "leaving as-is"
if [[ ! -f "$ROOT/edited" ]]; then ok "no gh pr edit issued"; else no "no gh pr edit issued" "edit file exists"; fi
echo ""

echo "3. --force-desc overwrites a real description"
reset_state "$ROOT/human_body"
OUT=$(run_gxpush --force-desc)
contains "reports the update" "$OUT" "updated on PR #4242"
EDITED=$(cat "$ROOT/edited" 2>/dev/null)
contains "body replaced with generated" "$EDITED" "### Generated title"
lacks "human text gone" "$EDITED" "A human already wrote this properly."
echo ""

echo "4. --no-desc never touches the PR"
reset_state "$REPO/.github/pull_request_template.md"
OUT=$(run_gxpush --no-desc)
contains "reports skip" "$OUT" "skipped (--no-desc)"
if [[ ! -f "$ROOT/edited" ]]; then ok "no gh pr edit issued"; else no "no gh pr edit issued" "edit file exists"; fi
echo ""

echo "5. Completely empty PR body — filled with description only"
printf '' > "$ROOT/empty_body"
reset_state "$ROOT/empty_body"
OUT=$(run_gxpush)
contains "reports missing" "$OUT" "description: missing"
EDITED=$(cat "$ROOT/edited" 2>/dev/null)
contains "has generated title" "$EDITED" "### Generated title"
lacks "no template injected" "$EDITED" "<details>"
echo ""

echo "6. No PR exists and no --pr — nothing created"
reset_state ""
OUT=$(run_gxpush)
lacks "does not mention an existing PR" "$OUT" "Existing PR"
if [[ ! -f "$ROOT/edited" ]]; then ok "no PR created"; else no "no PR created" "edit file exists"; fi
echo ""

echo "7. No PR exists, --pr given — creates one with a description"
reset_state ""
OUT=$(run_gxpush --pr)
contains "reports creation" "$OUT" "Creating PR..."
EDITED=$(cat "$ROOT/edited" 2>/dev/null)
contains "created body has description" "$EDITED" "### Generated title"
echo ""

echo "8. Closes #N still injected from a gh-NNN branch"
(cd "$REPO" && git checkout -qb fix/gh-321-thing && echo x > y.txt && git add -A && git commit -qm y)
reset_state "$ROOT/empty_body"
run_gxpush > /dev/null
EDITED=$(cat "$ROOT/edited" 2>/dev/null)
contains "body contains Closes #321" "$EDITED" "Closes #321"
(cd "$REPO" && git checkout -q feat/thing)
echo ""

echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="
[[ "$FAIL" -eq 0 ]]
