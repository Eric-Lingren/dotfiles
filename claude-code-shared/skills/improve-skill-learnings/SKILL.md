---
name: improve-skill-learnings
description: >
  Apply captured learnings from unified-learnings.jsonl to their target skill,
  agent, process, or contract files. Shows a ranked table of targets by unactioned
  learning count, lets the user pick one, validates all learnings for that target
  upfront via Haiku agents, then presents valid learnings one at a time for
  cherry-pick, diff approval, and commit. Auto-loops within the selected target
  until the user stops or the list is empty. Covers all four improves_type values:
  skill, agent, process, contract. Use when you want to act on accumulated
  learnings: "/improve-skill-learnings".
model: sonnet
effort: high
invokedBy: human
---

# Improve Skill Learnings

Apply captured learnings from `unified-learnings.jsonl` to their target files.

## Step 1: Load and filter learnings

Run the following to load all `status == "captured"` entries. Entries with no
`status` field are treated as `captured` (legacy entries predate the field).

```bash
python3 - <<'PYEOF'
import json, os
from collections import defaultdict
from datetime import datetime, timezone

path = os.path.expanduser(
    "~/.dotfiles/claude-code-shared/learnings/unified-learnings.jsonl"
)
entries = []
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    e = json.loads(line)
                    if e.get("status", "captured") == "captured":
                        entries.append(e)
                except json.JSONDecodeError:
                    pass
except FileNotFoundError:
    pass

groups = defaultdict(list)
for e in entries:
    key = e.get("improves") or "__unassigned__"
    groups[key].append(e)

now = datetime.now(timezone.utc)

def age_str(items):
    oldest = None
    for e in items:
        ts = e.get("timestamp")
        if ts:
            try:
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                if oldest is None or dt < oldest:
                    oldest = dt
            except (ValueError, TypeError):
                pass
    if oldest is None:
        return "?"
    days = (now - oldest).days
    if days < 1:
        return "<1d"
    if days < 14:
        return f"{days}d"
    weeks = days // 7
    if weeks < 9:
        return f"{weeks}w"
    return f"{days // 30}mo"

sorted_groups = sorted(groups.items(), key=lambda x: -len(x[1]))

print(f"TOTAL={len(entries)}")
for rank, (target, items) in enumerate(sorted_groups, 1):
    display = target if target != "__unassigned__" else "(unassigned)"
    itype = items[0].get("improves_type", "—")
    ids = ",".join(e["id"] for e in items)
    print(f"RANK={rank}|TARGET={target}|TYPE={itype}|COUNT={len(items)}|OLDEST={age_str(items)}|IDS={ids}|DISPLAY={display}")
PYEOF
```

Parse the output into a ranked table:

```
Rank | Target              | Type     | Learnings | Oldest
-----|---------------------|----------|-----------|-------
  1  | debug               | skill    | 4         | 3mo
  2  | to-seed             | skill    | 3         | 2w
  ...
  N  | (unassigned)        | —        | 2         | 5d
```

If `TOTAL=0`, print:

```
No captured learnings found. Nothing to do.
```

And stop.

## Step 2: User selects target

Ask the user which target they want to improve. Accept a rank number or a slug
name. Wait for the response.

If you use AskUserQuestion, pass at most 4 options (the tool maximum). If the
ranked list has more than 4 targets, pass only the top 4. Lower-ranked targets
stay reachable because the user can type a rank number or slug in the built-in
"Other" free-text option.

Collect all captured entries for the selected target (by their `id` values from
step 1).

## Step 3: Validate all learnings for target upfront

Spawn one Haiku validation agent per learning in a **single parallel Agent call**.
This runs before showing the picker so stale/invalid entries never appear.

For each learning, construct a `path_candidates` list based on `improves_type`:

| improves_type | Paths to check (in order) |
|---------------|--------------------------|
| `skill`       | `~/.dotfiles/claude-code-shared/skills/<improves>/SKILL.md` |
| `agent`       | `~/.dotfiles/claude-code-shared/agents/<improves>.md` |
| `process`     | `~/.dotfiles/claude-code-shared/resources/<improves>.md`, then `~/.dotfiles/claude-code-shared/resources/<improves>.json` |
| `contract`    | `~/.dotfiles/claude-code-shared/contracts/<improves>.json`, then `~/.dotfiles/claude-code-shared/contracts/<improves>.md` |

Pass this prompt to each Haiku agent (model: haiku):

```
You are a learning validation agent. Assess one learning entry and return a JSON verdict.

Learning entry:
  id: {id}
  improves: {improves}
  improves_type: {improves_type}
  problem: {problem}
  lesson: {lesson}
  fix: {fix}

Target file paths to check (in order):
{path_candidates — one per line}

Steps:
1. Check whether each path exists (use Bash: test -f <path> && echo exists).
   If none exist → return {"id": "{id}", "verdict": "invalid", "reason": "file_not_found", "file_path": null}
2. Read the first file that exists (Read tool).
3. Does the file ALREADY contain the substance of the fix or lesson?
   If yes → return {"id": "{id}", "verdict": "stale", "reason": "already_applied", "file_path": "<path>"}
4. Does this file itself perform the action the fix changes (e.g. edit code, spawn
   the agent, run the command)? If it only delegates that action to another skill
   or agent (e.g. an orchestrator skill that hands code edits to a runner agent) →
   return {"id": "{id}", "verdict": "misrouted", "reason": "<delegate file path>",
   "file_path": "<path>", "suggested_improves": "<slug>", "suggested_improves_type": "<skill|agent|process|contract>"}
5. Does the step or mechanism the fix changes live in a DIFFERENT file? (e.g. the
   fix edits an evidence-pack step, but this file has none.) Grep
   ~/.dotfiles/claude-code-shared/{skills,agents,resources,contracts} for the
   mechanism's distinctive terms. If exactly one other file clearly owns it →
   return {"id": "{id}", "verdict": "misrouted", "reason": "<owner file path>",
   "file_path": "<path>", "suggested_improves": "<slug>", "suggested_improves_type": "<skill|agent|process|contract>"}
6. Has the file changed so significantly that the lesson is no longer relevant?
   If yes → return {"id": "{id}", "verdict": "stale", "reason": "no_longer_relevant", "file_path": "<path>"}
7. Otherwise → return {"id": "{id}", "verdict": "valid", "reason": "ok", "file_path": "<path>"}

Return ONLY the JSON object. No prose.
```

Collect all verdicts. The resolved `file_path` from a valid entry is the
canonical target path for the diff.

## Step 4: Process validation results and build picker list

For each verdict where `verdict` is `stale` or `invalid`, run:

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/update-learning.py \
  --id <id> \
  --status <stale|invalid>
```

For each `misrouted` verdict, retarget it so it shows up under its real owner
(status stays `captured`):

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/update-learning.py \
  --id <id> \
  --improves <suggested_improves> \
  --improves-type <suggested_improves_type>
```

Treat any verdict outside `valid|stale|invalid|misrouted` as malformed. Read its
prose: if it names another owner, handle it as `misrouted`; otherwise as `stale`.

Print a validation summary:

```
Validation complete for <target>:
  Valid:      N
  Retargeted: N  (<id> → <new slug>, one per line)
  Stale:      N  (marked via update-learning.py)
  Invalid:    N  (marked via update-learning.py — file not resolvable)
```

If zero valid learnings remain, print:

```
All learnings for <target> are stale or invalid. Nothing to apply.
```

Then show the Summary Report (Step 8) and stop.

Otherwise, proceed to the **pick-one loop** (Steps 5-7).

## Step 5: Pick-one loop — show valid learnings and let user choose

Display the valid learnings as a numbered sub-list. Show only the `problem`
field per entry (one line each). Example:

```
Valid learnings for <target> (<N> remaining):

  1. filename versioning double-encoded when internal schema_version exists
  2. cleanup step uses shell rm, blocked by destructive-fs hook
  3. accuracy persona silently returns empty on large transcripts

Pick a learning to apply (number), or "done" to stop:
```

Wait for user response. If "done" or equivalent, jump to Step 8 (summary).

## Step 6: Draft diff for selected learning

Read the target file (resolved `file_path` from validation). Spawn a
session-model agent (subagent_type: general-purpose) with this prompt:

**Always spawn the drafting agent. Drafting the diff inline in your own turn is
a process violation, because the drafter works from the file and the learning
alone, without this session's context and assumptions. You may add extra
constraints to its prompt (style rules, which section to touch), not the diff.**

```
You are drafting a unified diff to apply ONE learning to a target file.

Target file: {file_path}

Current file content:
<file>
{full content of file_path}
</file>

Learning to apply:
  id: {id}
  problem: {problem}
  lesson: {lesson}
  fix: {fix}

Instructions:
1. Read the learning's `fix` field carefully.
2. Produce a standard unified diff (diff -u format) suitable for `patch -p0`.
3. Be minimal and surgical. Do not rewrite sections unrelated to this learning.
4. Include 3 context lines before and after each change hunk.
5. Return ONLY the diff, starting with "--- " and ending after the last hunk.
   No prose, no explanation.
```

Present the diff to the user. Keep the header as plain text outside the fence.
Put the diff in a fence tagged `diff` so added lines render green and removed
lines red. An untagged fence renders every line the same color.

````
**Proposed changes to `<file_path>`**
Learning <id>: <problem, one line>

```diff
<diff content>
```

Apply? [y/n]
````

Wait for response.

- `n` or rejection: Print "Skipped." Do NOT mark the learning as applied.
  Jump back to Step 5 (show remaining list without the skipped one).
- `y` or acceptance: Proceed to Step 7.

## Step 7: Apply, commit, and loop

Apply each hunk of the approved diff with the Edit tool. Do NOT pipe the diff
to `patch`. Agent-generated diffs pass through model text output and may
contain HTML-escaped entities (e.g. `&lt;`, `&gt;`, `&amp;`) that corrupt a
patch. Use the literal file text as `old_string`/`new_string`, unescaping any
entities first.

If an Edit fails (old_string not found), the diff's context drifted from the
real file. That is a drafting failure, not a problem with the learning. Re-read
the file and re-anchor the hunk against the current text once. If it still
fails, report the error and skip. Leave the learning `captured` (it stays in
the backlog for a later run). Jump back to Step 5 with the remaining list.

Mark the learning as applied:

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/update-learning.py \
  --id <id> --status applied
```

Commit:

```bash
git add <file_path>
git commit -m "improve(<target>): apply learning <short problem summary>"
```

Keep the commit message subject under 50 chars. Use a truncated version of the
`problem` field if needed.

**Auto-loop:** Remove the applied learning from the valid list. If valid
learnings remain, jump back to Step 5 and show the updated list. If none
remain, print "All valid learnings for <target> applied." and continue to
Step 8.

## Step 8: Summary report

Re-read unified-learnings.jsonl to tally the remaining backlog:

```bash
python3 - <<'PYEOF'
import json, os
from collections import defaultdict

path = os.path.expanduser(
    "~/.dotfiles/claude-code-shared/learnings/unified-learnings.jsonl"
)
groups = defaultdict(int)
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    e = json.loads(line)
                    if e.get("status", "captured") == "captured":
                        key = e.get("improves") or "(unassigned)"
                        groups[key] += 1
                except json.JSONDecodeError:
                    pass
except FileNotFoundError:
    pass

for target, cnt in sorted(groups.items(), key=lambda x: -x[1]):
    print(f"  {target}: {cnt}")
PYEOF
```

Display:

```
Summary for <target>:
  Applied: N  (one commit each)
  Skipped: N  (user declined)
  Retargeted: N  (moved to correct owner, still captured)
  Stale:   N  (marked stale, filtered before picker)
  Invalid: N  (marked invalid, filtered before picker)

Remaining backlog (<M> total across all targets):
  <slug1>: N learnings
  <slug2>: N learnings
  ...
  (unassigned): N learnings
```

If the backlog is empty, print "Backlog clear. No remaining captured learnings."

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `improve-skill-learnings`.
<!-- skill-done: improve-skill-learnings -->
<!-- learning-capture:end -->

## Step 9: Final outcome line

After the learning-capture agent finishes (or while it runs in background),
print a single concise outcome line so the user sees the result without scrolling
back. Format:

```
<target>: <N> applied, <N> skipped, <N> retargeted, <N> stale, <N> invalid. Backlog: <M> remaining.
```

This is the LAST thing printed. It must appear after the learning-capture tail
block, not before it.
