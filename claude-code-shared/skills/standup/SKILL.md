---
name: standup
description: Generate a team standup report from your current-cycle Linear tickets and GitHub PRs. Fetches live data, builds structured JSON, writes prose, and renders the report to the terminal. Saves the report to Quaestor-Web/docs/standups/YYYY-MM-DD.md. Use when the user says /standup, "standup", "morning standup", "daily standup", or "what did I work on".
model: sonnet
effort: medium
invokedBy: human
---

# Standup

Generate a short, win-heavy async standup update (Shipped, In flight, Blockers) from today's GitHub PR and Linear ticket data. Every ticket and PR in the output is a clickable link.

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

```bash
TMP=$(mktemp -d)
echo "$GH_JSON"     > "$TMP/github.json"
echo "$LINEAR_JSON" > "$TMP/linear.json"
bash ~/.dotfiles/claude-code-shared/scripts/standup/build-standup-data.sh \
  "$TMP/linear.json" "$TMP/github.json" \
  --standups-dir "$STANDUPS_DIR" > "$TMP/data.json"
```

`data.json` is large. Do not cat it. Read only the fields you need: ticket `key`/`title`/`parentKey` per group, and per PR `number`, `bucket`, `reviewDecision`, `age_days`.

`blockers` is split by cause. A PR appears under every cause it hits:

| Cause | Meaning | Whose move |
|---|---|---|
| `ci_failing` | CI is red | mine |
| `changes_requested` | a reviewer requested changes (GitHub `reviewDecision`) | mine |
| `unresolved_threads` | open review threads | mine |
| `stale_review` | still needs review, no activity for `--stale-days` (default 3) | reviewers |

`age_days` counts from the PR's last activity, so a fresh push resets it.

### 5. Write prose (model turn)

Write `prose.json` with the Write tool (not a python one-liner), e.g. `/tmp/standup-prose-YYYYMMDD.json`:

```json
{
  "shipped": {
    "lead": "Five wins landed since last standup, spanning dashboard polish and new field types.",
    "items": [
      "Smoother column rearranging in the Portfolio Dashboard ({KEY-2956})",
      "Date UI component, the base for the rest of the date work ({KEY-2376})"
    ]
  },
  "in_flight": {
    "lead": "Multi-select is moving fast, and the date stack is lined up right behind it.",
    "items": [
      "Multi-select: the core cell, row type and paste helper are all in review ({KEY-3788}, {KEY-3789}, {KEY-3790})",
      "Next up: wiring multi-select into the company metrics table ({KEY-3791}, {KEY-3792})"
    ]
  },
  "blockers": {
    "lead": "Mostly in my hands: a few CI fixes and some review feedback, plus one review to unstick.",
    "items": [
      "Fixing CI on {#20363} ({KEY-3788}) and {#19649} ({KEY-2464})",
      "Addressing requested changes on {#19657} ({KEY-2468})",
      "Need eyes on {#19654} ({KEY-2466}), waiting 7 days"
    ]
  }
}
```

**Links.** Write every ticket as `{KEY-123}` and every PR as `{#123}`. The renderer turns them into clickable links. A bare `KEY-123` or `#123` fails the render.

**Tone.** Positive, optimistic, win-heavy. Each section opens with one short narrative `lead` sentence, then tight bullets. Describe outcomes for users or the team, not PR titles. No em dashes. No hedging.

**Shipped.** One bullet per `done_new` item, each naming its ticket (or PR when there is no ticket). If `done_new` is empty, cover `done_earlier` instead (the header switches to "Shipped this cycle"). Lead with the count and the theme of the wins.

**In flight.** Group by workstream, not by ticket. Use the bracket tag in titles (`[multi-select]`, `[date]`) or `parentKey`/`epicKey` to group. Cover:
- non-blocker PRs in `in_review`, grouped (yellow = in review, green = approved: call it out as a win)
- the next `todo` tickets in the active workstream, as "Next up"
- the parent epic, when it ties the work together

Do not list every todo ticket. 2 to 5 bullets.

**Blockers.** One bullet per cause that has entries, in this order and phrasing:
- `ci_failing`: "Fixing CI on {#N} ({KEY})..."
- `changes_requested`: "Addressing requested changes on {#N} ({KEY})..."
- `unresolved_threads`: "Resolving open threads on {#N} ({KEY})..."
- `stale_review`: "Need eyes on {#N} ({KEY}), waiting N days". Name the reviewer only if one is clearly pending.

Never write "need eyes on" for a cause that is mine to fix. Every blocker PR must be referenced. The lead frames ownership positively (e.g. "Mostly in my hands..."). If there are no blockers, write a lead like "No blockers today." with an empty `items` list.

### 6. Render the report

```bash
REPORT=$(bash ~/.dotfiles/claude-code-shared/scripts/standup/render-standup.sh \
  "$TMP/data.json" "/tmp/standup-prose-YYYYMMDD.json")
```

On a non-zero exit, stderr lists every validation error (bare or unknown reference, em dash, missing lead, unreferenced shipped item or blocker PR, over 30 words per line, too many items). Fix `prose.json` and retry, at most twice.

### 7. Print the report to the terminal

Print `$REPORT` verbatim. Nothing else goes between it and the save step.

### 8. Save to standups directory

```bash
bash ~/.dotfiles/claude-code-shared/scripts/standup/resolve-standups-dir.sh --ensure
TODAY=$(date +%Y-%m-%d)
echo "$REPORT" > "$STANDUPS_DIR/$TODAY.md"
echo "Saved to $STANDUPS_DIR/$TODAY.md"
```

The `--ensure` flag creates `docs/standups/` and idempotently adds `docs/standups/` to the repo's `.git/info/exclude`. It never modifies `.gitignore`. The filename date also sets the "since last standup" cutoff for the next run.

## Output shape

```
**Shipped since last standup** 🚀
<lead sentence>
- <win> ([KEY-1](...))

**In flight** ⚡
<lead sentence>
- <workstream status> ([KEY-2](...), [KEY-3](...))

**Blockers** 🚧
<lead sentence>
- Fixing CI on [#101](...) ([KEY-4](...))
```

## Notes

- No flags or arguments. /standup always runs the full flow.
- Do not use the Linear MCP. All data comes from the fetch scripts.
- Do not include a "waiting on my review" section.
- The skill saves the report but does not commit it (Quaestor-Web uses a separate commit workflow).

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `standup`.
<!-- skill-done: standup -->
<!-- learning-capture:end -->
