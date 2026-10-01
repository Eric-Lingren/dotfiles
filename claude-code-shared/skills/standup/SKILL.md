---
name: standup
description: Generate a daily standup report from GitHub PRs and Linear tickets. Fetches live data, builds structured JSON, writes prose, and renders the report to the terminal. Saves the report to Quaestor-Web/docs/standups/YYYY-MM-DD.md. Use when the user says /standup, "standup", "morning standup", "daily standup", or "what did I work on".
model: sonnet
effort: medium
invokedBy: human
---

# Standup

Generate a standup report from today's GitHub PR and Linear ticket data.

## Process

### 1. Resolve the standups directory

```bash
STANDUPS_DIR=$(bash ~/.dotfiles/claude-code-shared/scripts/resolve-standups-dir.sh)
```

If the script exits non-zero, print its stderr hint and stop.

### 2. Fetch GitHub PR data

```bash
GH_JSON=$(bash ~/.dotfiles/claude-code-shared/scripts/fetch-github-standup.sh)
```

Extract `key_ids` (a JSON array of Linear KEY strings):

```bash
KEY_IDS=$(echo "$GH_JSON" | python3 -c "import json,sys; print(','.join(json.load(sys.stdin)['key_ids']))")
```

### 3. Fetch Linear ticket data

```bash
LINEAR_JSON=$(bash ~/.dotfiles/claude-code-shared/scripts/fetch-linear-standup.sh "$KEY_IDS")
```

### 4. Build structured standup data

Write the JSON inputs to temp files, then run:

```bash
TMP=$(mktemp -d)
echo "$GH_JSON"     > "$TMP/github.json"
echo "$LINEAR_JSON" > "$TMP/linear.json"
DATA_JSON=$(bash ~/.dotfiles/claude-code-shared/scripts/build-standup-data.sh \
  "$TMP/linear.json" "$TMP/github.json" \
  --standups-dir "$STANDUPS_DIR")
```

### 5. Write prose (model turn)

Read the structured data carefully, then write a `prose.json` scratch file using the Write tool. Do NOT use a python one-liner to write JSON — use the Write tool directly.

`prose.json` shape:
```json
{
  "summaries": {
    "SM-3008": "One-line human summary of the ticket or PR",
    "101": "Summary for PR #101 when there is no matched ticket"
  },
  "theme": "One sentence picking from the evidence menu below.",
  "talk_track": [
    "Line 1: what shipped (mention only 🆕 done items by ticket title).",
    "Line 2: what is waiting and on whom.",
    "Line 3: what is next.",
    "Line 4 (optional): tie the theme to the Linear project or initiative."
  ]
}
```

**Summaries:** Write one short human-readable line per ticket key (or per PR number when there is no ticket). Cover what the work does, not what the PR title says.

**Theme sentence:** Choose one theme from this evidence menu, backed by `theme_signals` from the structured data:

- *Quality bar / no regressions* — when `ci_green_ratio >= 0.8`
- *Cross-team collaboration* — when `distinct_reviewers >= 3`
- *Small reviewable slices* — when `small_prs >= 3`
- *Careful spec for accuracy and consistency* — when `delivery_count == 0` (no merges yet this cycle)
- *Steady delivery* — when `delivery_count >= 1` (default positive signal)

Wording is free — pick the strongest signal, write naturally, avoid jargon.

**Talk track rules:**
- 3–4 lines total, under 60 words total.
- Mention only 🆕 done items (from `done_new`). Do not list items still in review or in progress.
- Phrase blockers as "need eyes on #X from Y" or "next step is Z" — never as complaints.
- Tie the theme to the Linear project name (`projectName`) when available.
- Silver-lining tone: focus on momentum, not friction.

Write `prose.json` to a scratch path, e.g. `/tmp/standup-prose-YYYYMMDD.json`.

### 6. Render the report

```bash
REPORT=$(bash ~/.dotfiles/claude-code-shared/scripts/render-standup.sh \
  "$TMP/data.json" "/tmp/standup-prose-YYYYMMDD.json")
```

If render exits non-zero (talk track validation failed), revise the talk track in `prose.json` and retry once.

### 7. Print the report to the terminal

Print `$REPORT` verbatim (the full markdown report).

### 8. Save to standups directory

```bash
bash ~/.dotfiles/claude-code-shared/scripts/resolve-standups-dir.sh --ensure
TODAY=$(date +%Y-%m-%d)
echo "$REPORT" > "$STANDUPS_DIR/$TODAY.md"
echo "Saved to $STANDUPS_DIR/$TODAY.md"
```

The `--ensure` flag creates `docs/standups/` and idempotently adds `docs/standups/` to the repo's `.git/info/exclude`. It never modifies `.gitignore`.

## Output section order

The rendered report uses this section order: **In Review, Done, In Progress, Blockers, Theme, Talk track**.

- **Done:** 🆕 entries first (new merges), then one-line "Earlier this cycle: …" with links to older merges. When no prior standup file exists, all merged PRs appear as 🆕.
- **In Review:** state emoji (🔴 needs attention, 🟡 waiting on reviewers with age, 🟢 approved, ⚪ draft), ticket link, PR link, reviewer names.
- **In Progress:** includes draft PRs and tickets with no PR yet (tagged "(no PR yet)").
- **Blockers:** red-bucket PRs only. Phrased as "need eyes on" in the talk track, not in the rendered section.
- **Violations** (⚠️): multiple PRs per ticket, or status disagreement, marked inline.

## Notes

- No flags or arguments — /standup always runs the full flow.
- Do not use the Linear MCP. All data comes from the fetch scripts.
- Do not include a "waiting on my review" section.
- The skill saves the report but does not commit it (Quaestor-Web uses a separate commit workflow).

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `standup`.
<!-- skill-done: standup -->
<!-- learning-capture:end -->
