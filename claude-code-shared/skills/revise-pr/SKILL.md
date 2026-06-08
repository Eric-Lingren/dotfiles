---
name: revise-pr
description: >
  Post-publish PR feedback ingestion skill. Harvests reviewer and bugbot comments from an
  already-published PR, runs provisional triage, applies mandatory diligence, presents an
  HITL confirmation gate, fires attribution-tracer for confirmed escapes, and stops at a
  verified seed. Use when the user says "revise PR", "process PR feedback", "review my PR
  comments", or invokes /revise-pr.
slug: revise-pr
model: sonnet
effort: high
---

<!-- tier-delegate: managed by sync-model-tiers.py -->
## Delegate menial lookups to Haiku (cost control)

During this skill, push pure read-only lookups DOWN to a cheap subagent instead
of running them on the current model. This covers: multi-file grep/glob,
"where is X defined / what calls Y", mapping a directory, reading many files to
locate something, or fetching a URL for reference.

Use the Agent tool with the `caveman:cavecrew-investigator` subagent (Haiku,
returns a compressed file:line answer). If that subagent is unavailable, spawn a
general agent with `model: haiku`. Keep all reasoning, decisions, and edits on
the current model. Delegate only the menial searching.
<!-- /tier-delegate -->

## Scope

This skill processes feedback on PRs the **user already published** (post-review ingestion).
It is not for pre-vetting your own code before publishing (use `/code-review` for that) and
not for reviewing someone else's PR (use `/code-review` for that too). It does not post
GitHub comments, resolve threads, or push code during its own run. All outward writes are
deferred to downstream skills.

---

## Step 1 — Input: resolve the PR URL

**Primary:** Accept a PR URL as the skill argument (ARGUMENTS field).

**Fallback (no URL given):** Run:
```bash
gh pr list --author @me --state open
```
Present the output as a numbered list. Prompt the user to pick one. Use the selected PR URL
for all subsequent steps.

## Step 2 — Repo assertion

Resolve the PR's **base** repository from the GitHub API (the repo the PR targets, not the
fork it originates from). For fork-based PRs `headRepository` is the fork and would fail the
assertion against cwd. Use `baseRepository`:
```bash
gh pr view <url> --json baseRepository --jq '.baseRepository.nameWithOwner'
```

Resolve the cwd repository from git:
```bash
git remote get-url origin
```
Normalize both to `owner/repo` form (strip protocol, `.git` suffix, hostname).

**If they differ:** print a clear error message naming both repos and stop immediately.
Do not proceed. Example:
```
Error: PR repo (acme/api) does not match cwd repo (acme/frontend). cd into the correct repo and re-run.
```

## Step 3 — GraphQL harvest

### 3a. Get authenticated user

```bash
gh api user --jq '.login'
```
Store as `$me`. Used to filter self-authored comments at harvest time.

### 3b. Resolve GraphQL hostname

Extract hostname from the PR URL (e.g. `github.com`).

### 3c. GraphQL query

Call `gh api graphql` to fetch all review threads and comments. Use this query shape:

```graphql
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 50) {
            nodes {
              databaseId
              body
              url
              author { login }
            }
          }
        }
      }
      reviews(first: 100) {
        nodes {
          state
          body
          author { login }
          url
        }
      }
      comments(first: 100) {
        nodes {
          databaseId
          body
          url
          author { login }
        }
      }
    }
  }
}
```

Pass `-f owner=<owner> -f repo=<repo> -F number=<number>` as variables.

### 3d. SSO 403 handling

Inspect the GraphQL response for `errors[].message` containing `Resource not accessible by integration`.

**If detected:** Print the exact recovery command and stop:
```
Error: SSO authorization required for this organization.
Run: gh auth refresh -h <hostname>
Then re-run /revise-pr.
```

Do not attempt to continue with partial data.

### 3e. Harvest filter

From the GraphQL response, collect items as follows:

**Review threads** (`reviewThreads.nodes`):
- Keep only threads where `isResolved === false`.
- From each kept thread, take all `comments.nodes`.
- Exclude comments where `author.login === $me`.
- Known bugbot logins (e.g. `github-actions[bot]`, `dependabot[bot]`, `linear[bot]`, any
  login matching `*[bot]`) are included **regardless** of the self-author filter. Bugbot is
  a first-class source.
- After filtering, drop any thread that has zero remaining comments (a thread where every
  comment was self-authored). Such threads never reach the harvest display or triage.

**Review summary bodies** (`reviews.nodes`):
- Include all reviews where `body` is non-empty and `author.login !== $me`.
- Capture `state` (APPROVE / REQUEST_CHANGES / COMMENT) alongside the body.

**Top-level PR comments** (`comments.nodes`):
- Include all where `author.login !== $me`.
- Bot logins included as first-class sources.

### 3f. Display harvest output

Print a numbered list of harvested items. Each entry shows:
- Item number
- Source type (inline thread / review summary / PR comment)
- Author login
- Comment URL
- First 120 characters of body (truncated with `…` if longer)

If zero items remain after filtering, print:
```
No unresolved reviewer or bugbot comments found. Nothing to triage.
```
and stop.

---

## Step 4 — Provisional triage

After displaying the harvest list, auto-classify each item using a two-axis model.

### Axis 1: Class

Assign one of these classes to every item:

| Class | Meaning |
|-------|---------|
| `bug` | Claims the code has a defect (logic error, crash, incorrect output, security flaw) |
| `change` | Requests a different approach or refactor without claiming a defect |
| `question` | Asks for clarification; no action claimed required |
| `diligence` | Missing test, doc, or safety check |
| `discuss` | Design/architecture debate; no clear verdict yet |
| `nit` | Style or naming preference; non-blocking |

### Axis 2: Escape-disposition (bug class only)

For items classified as `bug`, assign one of these dispositions:

| Disposition | Meaning |
|-------------|---------|
| `unverified` | Default. The claim exists but has not been confirmed against code |
| `confirmed_escape` | Diligence confirmed the bug is real and it escaped code review |
| `false_flag` | Diligence showed the claim is incorrect; code is fine |
| `not_an_escape` | Bug is real but was a known tradeoff or intentional decision, not an escape |

**The skeptical default is `unverified`.** Never start a bug at `confirmed_escape`. Diligence (Step 5) is what moves the disposition.

### Triage table

Present the triage table to the user. Minimum columns:

| # | Excerpt (first 120 chars) | Class | Disposition |
|---|--------------------------|-------|-------------|
| 1 | "The nil check is missing..." | bug | unverified |
| 2 | "Consider extracting this..." | change | |
| 3 | "What does this fn return..." | question | |

The **Disposition** column appears only for `bug`-class items. Leave it blank for all other classes.

### User overrides

After presenting the table, prompt: "Override any classifications before diligence? Reply with row changes (e.g. '3: change → bug, unverified') or press Enter to accept."

Apply all stated overrides before proceeding.

**The triage table is a proposal only.** No action fires until the HITL confirmation gate in Step 6.

---

## Step 5 — Mandatory universal diligence gate

**This gate is non-optional.** Every harvested item must pass through it. There is no bypass path. Partial completion (leaving any item without an explicit verdict) is not allowed before proceeding to Step 6.

`revise-pr` is the only untrusted data inlet in the pipeline. Reviewer and bugbot comments are unverified claims. Other ingestion skills (debug, grill-me, code-review) start from pre-verified human or ruleset input; this one does not. Diligence is what makes the output trustworthy.

### Per-item diligence

For each harvested item, surface these three pieces of context side by side:

1. **Flagged claim text** — the reviewer's exact words verbatim (full body, not truncated)
2. **Originating comment URL** — the direct link from harvest
3. **Relevant code context** — the relevant section from the PR diff (use `gh pr diff <url>`) or the referenced file, focused on the exact lines the comment addresses

Present these together so the user can evaluate the claim against the actual code in one view.

### Diligence verdicts

The user renders one of these verdicts for each item.

**Bug-class items** take one of these dispositions:

| Verdict | Meaning |
|---------|---------|
| `confirmed_escape` | Bug is real and escaped code review — it should have been caught |
| `false_flag` | The claim is incorrect; the code is fine as written |
| `not_an_escape` | Bug is real but was a known tradeoff or intentional decision |
| `unverified` | Still uncertain after diligence; needs more investigation |

**Non-bug items** (`change`, `question`, `diligence`, `discuss`, `nit`) take the verdict
`reviewed` once the user has looked at the claim against the code and confirmed it does not
reclassify to a bug. `reviewed` is the explicit verdict that satisfies the gate exit
condition for non-bug items; it carries no disposition. If diligence promotes a non-bug item
to `bug`, it then takes one of the four bug dispositions above instead.

### Reconciliation

Diligence may change an item's classification, not just its disposition. Examples:
- A `question` that turns out to be a real bug → promote to `bug, confirmed_escape`
- A `bug` that the reviewer misread → demote to `false_flag`
- A `diligence` item that is actually just a nit → reclassify to `nit`

Update the triage table row for any item whose class or disposition changes during diligence.

### Gate exit condition

No item may exit this gate without an explicit verdict. Bug-class items need one of the four
dispositions; non-bug items need `reviewed`. Do not proceed to Step 6 until every item has a
diligence verdict recorded.

Note: when the `vet` skill is built, it slots into this gate as the automated diligence executor. For v1, diligence is manual.

---

## Step 6 — HITL confirmation gate

This is the last human checkpoint before any action proceeds. No action fires until this gate is passed.

Present the post-diligence classification as a confirmation table:

| # | Excerpt | Final Class | Disposition | Action |
|---|---------|-------------|-------------|--------|
| 1 | "The nil check..." | bug | confirmed_escape | attribution-tracer |
| 2 | "Consider extracting..." | change | | none |
| 3 | "What does fn return..." | question | | relay (notify) |

The **Action** column shows what will fire for each item after the user confirms:
- `confirmed_escape` bugs: attribution-tracer will be spawned
- `false_flag`, `not_an_escape`, `unverified` bugs: no action
- Non-bug items: noted in provenance for relay

Prompt the user: "Confirm this categorization and proceed, or override any row before actions fire."

Apply any final overrides. Then proceed to Step 7.

---

## Step 7 — Attribution-tracer invocation

After the HITL gate is confirmed, for each item whose **final disposition is `confirmed_escape`**:

Spawn one `attribution-tracer` subagent with these exact inputs:
- `issue_description`: the confirmed defect claim text (the reviewer's exact words)
- `pr_url`: the PR URL from Step 1
- `branch`: the PR head branch, resolved via `gh pr view <url> --json headRefName --jq '.headRefName'`
- `transcript_path`: absolute path to the current session transcript

Attribution fires **once per `confirmed_escape` item**, not once per session. Each item gets its own attribution-tracer call.

**Items that must never trigger attribution-tracer:**
- `false_flag` disposition
- `not_an_escape` disposition
- `unverified` disposition
- Any non-bug class item

The `fix` field in the generated attribution record will be empty or TBD. This is intentional. The escape is being attributed before a fix exists; downstream sessions will confirm or fill the fix. Attribution demotes to candidate/`improves: null` when the escape is ambiguous.

**Invariant: this skill never makes outward HTTP writes during its own run.** No GitHub comment is posted. No review thread is resolved. No branch is checked out or pushed. All such actions are deferred to downstream skills (`relay`, `build-code`, etc.).

---

## Step 8 — Seed stop

After attribution-tracer has run for all `confirmed_escape` items, invoke `/to-seed`. Pass the full session context plus the structured provenance block below.

### Provenance block

Build and include this provenance block in the seed:

```json
{
  "pr_url": "<the PR URL from Step 1>",
  "head_branch": "<the PR head branch resolved in Step 7>",
  "items": [
    {
      "thread_id": "<the id value>",
      "thread_id_type": "graphql_node_id | database_id",
      "final_class": "<final class after diligence and HITL gate>",
      "disposition": "<final disposition for bug items, or null>"
    }
  ]
}
```

**ID type discipline:** the two GraphQL sources return different id kinds and they must not be
conflated. Inline review threads (`reviewThreads.nodes[].id`) yield an opaque GraphQL global
node ID string — set `thread_id_type` to `"graphql_node_id"`. Top-level PR comments and
thread comments expose a numeric `databaseId` — set `thread_id_type` to `"database_id"`.
A downstream consumer (e.g. `relay` resolving threads) keys its lookup on `thread_id_type`,
so the field is mandatory on every item. Prefer the thread `id` (graphql_node_id) for inline
threads since thread resolution operates on the thread, not an individual comment.

Include one entry per harvested item.

**Skill boundary:** This skill stops after `/to-seed` completes. It does not invoke `/to-tasks`, `/build-code`, branch checkout, or push. What the downstream pipeline does with the seed is outside this skill's concern.

---

## Step 9 — Relay stub (v1, inline)

After `/to-seed` completes, read `seed.provenance.items[]` from the written seed file. Resolve
the seed path from `/to-seed`'s terminal output (it prints the absolute path it wrote, under
`docs/seeds/`). Do not guess the filename. Filter to items with `final_class` in
`["question", "discuss", "nit"]`.

Print a formatted list to the user:

```
Non-code items for your attention:

1. [question] "What does this fn return when input is empty?"
   URL: https://github.com/...
2. [nit] "Rename `x` to something more descriptive"
   URL: https://github.com/...
```

No external calls are made from this step. No GitHub comments are posted. This is a notify-only print.

---

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `revise-pr`.
<!-- skill-done: revise-pr -->
  - `/to-tasks` — seed is verified and ready for implementation
  - `/relay` — non-code items need user notification
<!-- learning-capture:end -->
