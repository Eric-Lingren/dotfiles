---
name: standup
description: Generate a team standup report from your current-cycle Linear tickets and GitHub PRs. Fetches live data, builds structured JSON, writes prose, and renders the report to the terminal. Saves the report to Quaestor-Web/docs/standups/YYYY-MM-DD.md. Use when the user says /standup, "standup", "morning standup", "daily standup", or "what did I work on".
model: sonnet
effort: medium
invokedBy: human
---

# Standup

Generate a standup report from today's GitHub PR and Linear ticket data.

## Process

### 1. Resolve the standups directory

```bash
STANDUPS_DIR=$(bash ~/.dotfiles/claude-code-shared/scripts/standup/resolve-standups-dir.sh)
```

If the script exits non-zero, print its stderr hint and stop.

### 2. Fetch GitHub PR data

```bash
GH_JSON=$(bash ~/.dotfiles/claude-code-shared/scripts/standup/fetch-github-standup.sh)
```

Extract `key_ids` (a JSON array of Linear KEY strings):

```bash
KEY_IDS=$(echo "$GH_JSON" | python3 -c "import json,sys; print(','.join(json.load(sys.stdin)['key_ids']))")
```

### 3. Fetch Linear ticket data

```bash
LINEAR_JSON=$(bash ~/.dotfiles/claude-code-shared/scripts/standup/fetch-linear-standup.sh "$KEY_IDS")
```

### 4. Build structured standup data

Write the JSON inputs to temp files, then run:

```bash
TMP=$(mktemp -d)
echo "$GH_JSON"     > "$TMP/github.json"
echo "$LINEAR_JSON" > "$TMP/linear.json"
DATA_JSON=$(bash ~/.dotfiles/claude-code-shared/scripts/standup/build-standup-data.sh \
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
  "theme": "One sentence that leads with what shipped, then the supporting signal.",
  "shipped_track": [
    "Line 1: what shipped since last standup, by plain-English outcome.",
    "Line 2: what that unlocks, or the rest of what shipped this cycle.",
    "Line 3 (optional): more shipped work or its impact."
  ],
  "talk_track": [
    "Line 1: what is waiting and on whom.",
    "Line 2: what is next.",
    "Line 3 (optional): tie it to the Linear project or initiative."
  ]
}
```

**Summaries:** Write one short human-readable line per ticket key (or per PR number when there is no ticket). Cover what the work does, not what the PR title says. Every `done_new` and `done_earlier` entry needs a summary. Skip summaries for `todo` tickets; that section renders as a tight title list. These are the lines people remember, so describe the outcome for users or the team.

**Theme sentence:** Completed work comes first. When `shipped_cycle_count >= 1`, the sentence opens with what shipped this cycle (name the outcome, not a count alone). Then add the strongest supporting signal from `theme_signals`:

- *Steady delivery* — when `delivery_count >= 1` (shipped since last standup)
- *Quality bar / no regressions* — when `ci_green_ratio >= 0.8`
- *Cross-team collaboration* — when `distinct_reviewers >= 3`
- *Small reviewable slices* — when `small_prs >= 3`
- *Careful spec for accuracy and consistency* — only when `shipped_cycle_count == 0`

Wording is free. Write naturally, avoid jargon.

**Talk track rules.** The talk track is mostly about completed work. Lead with it, spend the most words on it.
- `shipped_track`: 1–3 lines. Required whenever `shipped_cycle_count >= 1` (render fails without it). Start with `done_new` items. If `done_new` is empty, lead with `done_earlier` ("Earlier this cycle we shipped…"). Name the outcome and who it helps. Mention 🆕 items by name before older ones.
- `talk_track`: 2–3 lines on what is waiting and what is next. Keep it short.
- 80 words max across both lists. Aim for more words in `shipped_track` than in `talk_track`.
- Phrase blockers as "need eyes on #X from Y" or "next step is Z", never as complaints.
- Tie the theme to the Linear project name (`projectName`) when available.
- Silver-lining tone: focus on momentum, not friction.
- Only when nothing shipped this cycle (`shipped_cycle_count == 0`): leave `shipped_track` empty and open `talk_track` with the closest-to-done item.

Write `prose.json` to a scratch path, e.g. `/tmp/standup-prose-YYYYMMDD.json`.

### 6. Render the report

```bash
REPORT=$(bash ~/.dotfiles/claude-code-shared/scripts/standup/render-standup.sh \
  "$TMP/data.json" "/tmp/standup-prose-YYYYMMDD.json")
```

If render exits non-zero (talk track validation failed), revise `shipped_track` / `talk_track` in `prose.json` and retry once.

### 7. Print the report to the terminal

Print `$REPORT` verbatim (the full markdown report).

### 8. Save to standups directory

```bash
bash ~/.dotfiles/claude-code-shared/scripts/standup/resolve-standups-dir.sh --ensure
TODAY=$(date +%Y-%m-%d)
echo "$REPORT" > "$STANDUPS_DIR/$TODAY.md"
echo "Saved to $STANDUPS_DIR/$TODAY.md"
```

The `--ensure` flag creates `docs/standups/` and idempotently adds `docs/standups/` to the repo's `.git/info/exclude`. It never modifies `.gitignore`.

## Output section order

The rendered report uses this section order: **🟣 Done, 🟢 In Review, 🟡 In Progress, ⚪ Todo, Blockers, Theme, Talk track**.

Circles match Linear's status colors: ⚪ todo/backlog, 🟡 in progress, 🟢 in review, 🟣 done/shipped. Each ticket line gets the circle for its actual Linear status, so a ticket whose color doesn't match its section is out of sync in Linear. Circles mean Linear status only. PR review health uses separate markers.

- **Done:** a "Shipped this cycle: N" count, then 🆕 entries (merged or completed since the last standup), then an "Earlier this cycle" subsection with full entries and summaries. Linear tickets marked Done with no PR count too. When no prior standup file exists, everything shipped this cycle is 🆕.
- **In Review:** PR markers (🚩 needs attention, ⏳ waiting on reviewers with age, ✅ approved), ticket link, PR link, reviewer names.
- **In Progress:** draft PRs (📝) and started tickets with no PR yet (tagged "(no PR yet)").
- **Todo:** tickets in Linear's triage, backlog, or unstarted states. Canceled tickets are dropped.
- **Blockers:** 🚩 PRs only. Phrased as "need eyes on" in the talk track, not in the rendered section.
- **Talk track:** `shipped_track` lines first, then `talk_track`.
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
