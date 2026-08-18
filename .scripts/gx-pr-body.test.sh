#!/usr/bin/env bash
# gx-pr-body.test.sh — Unit tests for PR body classification and template merging
# What: exercises gx-pr-body status/merge against empty, unfilled-template, ticked-template, and real-prose bodies
# When: after changing gx-pr-body or gxpush's PR description logic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/gx-pr-body"

PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
no() { echo "  FAIL: $1"; echo "        expected: [$2]"; echo "        actual:   [$3]"; FAIL=$((FAIL + 1)); }

eq() {
  if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1" "$2" "$3"; fi
}

contains() {
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else no "$1" "contains: $3" "$2"; fi
}

lacks() {
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else no "$1" "must not contain: $3" "$2"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TEMPLATE="$TMP/pr_template.md"
cat > "$TEMPLATE" <<'TPL'
## Summary

Provide at least a 1-2 sentence summary of what this PR changes.


<details>

   <summary><b>Data model or schema changes? Expand this section</b></summary>


- [ ] I have added or modified a data model that may hold user generated data, or anonymization code itself. ➔ Continue below.
  - [ ] I have made the appropriate changes to the anonymization management command to account for the above changes.

</details>
TPL

DESC="$TMP/desc.md"
cat > "$DESC" <<'DSC'
### Consolidate components tree docs
Linear Ticket: [KEY-1534](https://linear.app/standard-metrics/issue/KEY-1534)

Component docs were split across three files with no shared conventions.

**Changes:**
- Document the consolidated tree structure
DSC

echo "=== gx-pr-body tests ==="
echo ""

echo "1. status: blank body"
eq "blank -> empty" "empty" "$(printf '' | "$BIN" status --template "$TEMPLATE")"
eq "whitespace -> empty" "empty" "$(printf '   \n\n  \n' | "$BIN" status --template "$TEMPLATE")"
echo ""

echo "2. status: HTML-comment-only body"
eq "comments only -> empty" "empty" \
  "$(printf '<!-- describe your change -->\n\n<!-- checklist\nmulti\n-->\n' | "$BIN" status --template "$TEMPLATE")"
echo ""

echo "3. status: unfilled template (the PR 18763 case)"
eq "verbatim template -> template" "template" "$("$BIN" status --template "$TEMPLATE" < "$TEMPLATE")"
eq "CRLF template -> template" "template" \
  "$(sed 's/$/\r/' "$TEMPLATE" | "$BIN" status --template "$TEMPLATE")"
echo ""

echo "4. status: template with boxes ticked but no prose"
TICKED=$(sed 's/- \[ \]/- [x]/' "$TEMPLATE")
eq "ticked template -> template" "template" "$(printf '%s\n' "$TICKED" | "$BIN" status --template "$TEMPLATE")"
echo ""

echo "5. status: real prose"
eq "prose -> filled" "filled" \
  "$(printf '### Real title\n\nA human wrote this.\n' | "$BIN" status --template "$TEMPLATE")"
FILLED=$(sed 's/Provide at least a 1-2 sentence summary of what this PR changes./We refactored the exporter./' "$TEMPLATE")
eq "template with summary written -> filled" "filled" \
  "$(printf '%s\n' "$FILLED" | "$BIN" status --template "$TEMPLATE")"
echo ""

echo "6. merge: unfilled template keeps the compliance checklist"
MERGED=$("$BIN" merge --desc "$DESC" --template "$TEMPLATE" < "$TEMPLATE")
contains "keeps '## Summary' heading" "$MERGED" "## Summary"
contains "inserts generated title" "$MERGED" "### Consolidate components tree docs"
contains "inserts Linear link" "$MERGED" "Linear Ticket: [KEY-1534]"
lacks "drops placeholder line" "$MERGED" "Provide at least a 1-2 sentence summary"
contains "keeps <details> block" "$MERGED" "<details>"
contains "keeps checklist item" "$MERGED" "- [ ] I have added or modified a data model"
contains "keeps closing tag" "$MERGED" "</details>"
echo ""

echo "7. merge: description lands before the details block"
DESC_POS=$(printf '%s\n' "$MERGED" | grep -n "Consolidate components tree docs" | cut -d: -f1)
DET_POS=$(printf '%s\n' "$MERGED" | grep -n "<details>" | cut -d: -f1)
if [[ -n "$DESC_POS" && -n "$DET_POS" && "$DESC_POS" -lt "$DET_POS" ]]; then
  ok "description (line $DESC_POS) precedes <details> (line $DET_POS)"
else
  no "description precedes <details>" "desc < details" "desc=$DESC_POS details=$DET_POS"
fi
echo ""

echo "8. merge: empty body yields the description alone"
EMPTY_MERGE=$(printf '' | "$BIN" merge --desc "$DESC" --template "$TEMPLATE")
contains "has the description" "$EMPTY_MERGE" "### Consolidate components tree docs"
lacks "no template leaked in" "$EMPTY_MERGE" "<details>"
echo ""

echo "9. merge: body with no heading keeps existing content below"
NOHEAD=$(printf 'some stray note\n' | "$BIN" merge --desc "$DESC" --template "$TEMPLATE")
contains "description present" "$NOHEAD" "### Consolidate components tree docs"
contains "stray note preserved" "$NOHEAD" "some stray note"
echo ""

echo "10. no template in repo: prose still classifies as filled"
eq "no template, prose -> filled" "filled" \
  "$(printf 'real body\n' | "$BIN" status --repo-root "$TMP")"
eq "no template, blank -> empty" "empty" \
  "$(printf '\n' | "$BIN" status --repo-root "$TMP")"
echo ""

echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="
[[ "$FAIL" -eq 0 ]]
