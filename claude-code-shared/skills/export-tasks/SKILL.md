---
name: export-tasks
description: Export triage tasks from a task file to external destinations (GitHub Issues for code deliverables, personal Notion for non-code deliverables). Resolves each item's (deliverable, domain) pair against task-routing.json, shows a dry-run table with wall-crossing warnings, then writes to the matched adapter. Spawned by dispatch-tasks as an isolated agent. Use when dispatching triage items to external destinations.
model: sonnet
effort: high
spawn_mode: agent
---

# Export Tasks

Export triage-typed items from a task file to external destinations. Resolves routing via `task-routing.json`, shows a dry-run table for human review, and writes to the matched adapter. Updates item status and `export_url` on success.

**Spawn mode:** this skill is spawned as an isolated agent by `dispatch-tasks`. It receives the task file path as the sole argument.

## Contract

**Format:** task file — see `contracts/task-contract.md` (schema_version: `"2"`)
**Routing config:** `~/.dotfiles/claude-code-shared/resources/task-routing.json`
**Role:** triage branch executor

## Process

### 1. Load inputs

Read the task file path from the invocation argument.

Read `~/.dotfiles/claude-code-shared/resources/task-routing.json` to get the destinations map.

Filter the task file to items where:
- `task_type` is `triage`
- `status` is `not_started`

If no eligible items remain, print "No triage items to export." and exit cleanly.

### 2. Placeholder check

For each item in the run, resolve its route (see step 3 for flat vs split shape). Collect all Notion routes. For each Notion route, check whether `location` is a known placeholder value (`"personal-notion-db"`, `"ss-notion-db"`).

**If any required Notion location is a placeholder:**

```
ERROR: Notion DB ID not configured for <domain>/<deliverable>.

The location at destinations.<domain>.non-code.location is a placeholder value
('<placeholder>'). export-tasks cannot write to Notion without a real DB ID.

To find your Notion DB ID:
  1. Open Notion and navigate to the target database (not a page — the database itself).
  2. Click "Open as full page" if it's embedded.
  3. Copy the URL. It looks like:
       https://www.notion.so/My-Database-<DATABASE_ID>?v=<view-id>
     The DB ID is the 32-character hex string after the last '-' in the path
     and before the '?'. It may also appear without hyphens as a bare 32-char string.
  4. Edit ~/.dotfiles/claude-code-shared/resources/task-routing.json
  5. Replace the placeholder at destinations.<domain>.non-code.location with the real ID.
  6. Verify: jq '.destinations.<domain>["non-code"].location' ~/.dotfiles/claude-code-shared/resources/task-routing.json

See FU-001 in the task file for full steps.
```

Stop immediately if any required Notion DB ID is a placeholder. Do not write anything.

Also check: for any `auth=api-token` Notion route, source secrets first, then verify the token is set:

```bash
[ -f ~/.dotfiles/local/secrets.env ] && source ~/.dotfiles/local/secrets.env
echo $NOTION_PERSONAL_TOKEN
```

If empty after sourcing, print the setup instructions from the api-token section in step 6 and stop.

### 3. Resolve routing for each item

Destinations have two shapes. Check which shape applies to `item.domain`:

**Flat destination** (e.g. `standard-metrics`): `destinations[item.domain]` has a top-level `adapter` key. All deliverables route to the same adapter regardless of `deliverable`.

```
route = destinations[item.domain]
adapter = route.adapter   // e.g. "linear"
location = route.location
```

**Split destination** (e.g. `personal`, `spawned-sapien`): `destinations[item.domain]` has `code` and `non-code` sub-keys. Route by `item.deliverable`.

```
route = destinations[item.domain][item.deliverable]
adapter = route.adapter   // "github-issues" or "notion"
location = route.location // "current-repo" or a Notion DB ID
```

Resolve concrete targets:
- **github-issues + location=current-repo:** extract `Org/Repo` from `git remote get-url origin` (strip protocol/host, remove `.git` suffix). Use `--repo <Org/Repo>` in the gh CLI command.
- **notion:** use `location` as the Notion database ID. Use the Notion MCP (`mcp__claude_ai_Notion__` tools).
- **linear:** Linear adapter is deferred past v1. If a `linear` route is resolved, print a warning and skip the item: "Linear adapter not yet implemented. Item skipped."

### 4. Wall-crossing check

Read `destinations[item.domain].wall` from `task-routing.json`. Compare the resolved adapter's wall against the item's domain wall:
- `standard-metrics` domain (`wall: corporate`) routed to any non-corporate adapter: **HARD WALL VIOLATION**
- non-corporate item routed to a corporate adapter: **HARD WALL VIOLATION**
- `spawned-sapien` domain routed to `personal` Notion DB: **WARNING** (soft boundary — separate Notion workspace expected)

Flag violations in the dry-run table.

### 5. Dry-run table

Print the full plan before making any external write. Do not skip.

```
Export plan — docs/tasks/<filename>

 ID      Title                              Adapter        Target                    Deliverable
 ──────  ─────────────────────────────────  ─────────────  ────────────────────────  ───────────
 T-0010  Round-trip read side               notion         <db-id-prefix>...         non-code
 T-0011  Additional runners                 notion         <db-id-prefix>...         non-code
 T-0012  PR for remaining adapters          gh-issue       Eric-Lingren/dotfiles     code
WARNING: T-0013 — domain=standard-metrics item (wall=corporate) routed to personal Notion. Hard wall crossing. Remove from run or fix domain.

Review the plan above. Press Enter to proceed or type "abort" to cancel.
```

Hard wall violations show a WARNING line. If any hard wall violation exists, do not proceed until the user either removes the item from scope or corrects the domain. Ask the user to resolve each violation before continuing.

### 6. Execute writes

After user approval, write each item to its adapter in sequence:

#### GitHub Issues adapter

```bash
gh issue create \
  --title "<item.title>" \
  --body "<item.description>" \
  --label triage \
  --repo <Org/Repo>
```

Capture the issue URL from stdout (GitHub CLI prints `https://github.com/<org>/<repo>/issues/<number>`).

#### Notion adapter (non-code)

Check `route.auth` from `task-routing.json` to determine which write path to use.

**auth=mcp (Spawned Sapien workspace):**

Use the Notion MCP tools. Set `Status="Todo"` and `Type="Task"` to match the SS Tasks Tracker schema:

```
mcp__claude_ai_Notion__notion-create-pages(
  parent_database_id: "<resolved-db-id>",
  pages: [{
    title: "<item.title>",
    properties: {
      "Status": "Todo",
      "Type": "Task"
    },
    children: [{"paragraph": {"rich_text": [{"text": {"content": "<item.description>"}}]}}]
  }]
)
```

**auth=api-token (personal workspace):**

Check that `NOTION_PERSONAL_TOKEN` is set. If not, abort with:
```
ERROR: NOTION_PERSONAL_TOKEN is not set.

Steps:
  1. Go to notion.so/profile/integrations
  2. Create a new Internal integration, select your personal workspace
  3. Copy the secret (starts with ntn_)
  4. Copy ~/.dotfiles/local/secrets.env.template to ~/.dotfiles/local/secrets.env
  5. Uncomment and fill in: export NOTION_PERSONAL_TOKEN=ntn_...
  6. Open your personal Notion DB, click ... > Connections > add the integration
```

If set, write via the Notion REST API:

```bash
curl -s -X POST https://api.notion.com/v1/pages \
  -H "Authorization: Bearer $NOTION_PERSONAL_TOKEN" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{
    "parent": {"database_id": "<resolved-db-id>"},
    "properties": {
      "Name": {"title": [{"text": {"content": "<item.title>"}}]}
    },
    "children": [{"object":"block","type":"paragraph","paragraph":{"rich_text":[{"type":"text","text":{"content":"<item.description>"}}]}}]
  }'
```

Capture the `url` field from the JSON response.

Capture the returned page URL (MCP) or `url` field from the JSON response (API).

### 7. Update task file

After each successful write, immediately update the task file JSON:
- Set `item.status` to `"done"`
- Set `item.export_url` to the external URL (GitHub issue URL or Notion page URL)

Write the updated JSON to disk after each item (do not batch).

If a write fails for a specific item:
- Set `item.status` to `"blocked"`
- Log the error in the end-of-run summary
- Continue to the next item (do not abort the whole run)

### 8. End-of-run summary

```
Export complete — docs/tasks/<filename>

 ID      Title                              Result    Export URL
 ──────  ─────────────────────────────────  ────────  ─────────────────────────────────────────
 T-0010  Round-trip read side               done      https://notion.so/page-id-abc
 T-0011  Additional runners                 done      https://notion.so/page-id-def
 T-0012  PR for remaining adapters          done      https://github.com/org/repo/issues/42

Items exported: 3
Items failed: 0
```

<!-- learning-capture:start -->
## Learning Capture

Run this as the FINAL action of this skill's terminal turn, BEFORE printing the
closing suggestion or handoff. Most runs record nothing — only proceed if an
observable correction-event occurred this run.

<!-- learning-eval: export-tasks -->
If a correction-event occurred: identify the `trigger` (tool_failure | backtrack |
user_correction | instruction_gap | redundant_effort | uncategorized), a one-sentence
description of what happened (`brief_evidence`), and `trigger_label` (snake_case if
uncategorized, else null). Spawn the `capture-learning` agent
(`subagent_type: capture-learning`) with: `skill` (this skill's slug: `export-tasks`),
`trigger`, `trigger_label`, `brief_evidence`, `transcript_path` (absolute path to
session transcript). The agent builds the full schema-valid entry, runs grounding
verification, and writes if grounded.
**What's next:**
<!-- skill-done: export-tasks -->
  - `/dispatch-tasks` — return to dispatcher for next branch
<!-- learning-capture:end -->
