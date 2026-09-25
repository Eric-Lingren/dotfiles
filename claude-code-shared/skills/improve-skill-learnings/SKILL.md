---
name: improve-skill-learnings
description: >
  Apply captured learnings from unified-learnings.jsonl to their target skill,
  agent, process, or contract files. Shows a ranked table of targets by unactioned
  learning count, lets the user pick one, validates each learning via Haiku agents,
  drafts a cohesive diff for user approval, and auto-commits on acceptance. Covers
  all four improves_type values: skill, agent, process, contract. Use when you want
  to act on accumulated learnings: "/improve-skill-learnings".
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

sorted_groups = sorted(groups.items(), key=lambda x: -len(x[1]))

print(f"TOTAL={len(entries)}")
for rank, (target, items) in enumerate(sorted_groups, 1):
    display = target if target != "__unassigned__" else "(unassigned)"
    itype = items[0].get("improves_type", "—")
    ids = ",".join(e["id"] for e in items)
    print(f"RANK={rank}|TARGET={target}|TYPE={itype}|COUNT={len(items)}|IDS={ids}|DISPLAY={display}")
PYEOF
```

Parse the output into a ranked table:

```
Rank | Target              | Type     | Learnings
-----|---------------------|----------|----------
  1  | debug               | skill    | 4
  2  | to-seed             | skill    | 3
  ...
  N  | (unassigned)        | —        | 2
```

If `TOTAL=0`, print:

```
No captured learnings found. Nothing to do.
```

And stop.

## Step 2: User selects target

Ask the user which target they want to improve. Accept a rank number or a slug
name. Wait for the response.

Collect all captured entries for the selected target (by their `id` values from
step 1).

## Step 3: Validate learnings via Haiku agents

Spawn one Haiku validation agent per learning in a **single parallel Agent call**.

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
4. Has the file changed so significantly that the lesson is no longer relevant?
   If yes → return {"id": "{id}", "verdict": "stale", "reason": "no_longer_relevant", "file_path": "<path>"}
5. Otherwise → return {"id": "{id}", "verdict": "valid", "reason": "ok", "file_path": "<path>"}

Return ONLY the JSON object. No prose.
```

Collect all verdicts. The resolved `file_path` from a valid entry is the
canonical target path for the diff.

## Step 4: Process validation results

For each verdict where `verdict` is `stale` or `invalid`, run:

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/update-learning.py \
  --id <id> \
  --status <stale|invalid>
```

Print a validation summary before continuing:

```
Validation complete for <target>:
  Valid:   N
  Stale:   N  (marked via update-learning.py)
  Invalid: N  (marked via update-learning.py — file not resolvable)
```

If zero valid learnings remain, print:

```
All learnings for <target> are stale or invalid — nothing to apply.
```

Then show the Summary Report (Step 8) and stop.

## Step 5: Draft the unified diff

All valid learnings must share the same `file_path` (the validation agent resolved
it in step 3). If they somehow resolve to different files, tell the user and ask
which file to target before proceeding.

Spawn a session-model agent (subagent_type: general-purpose) with this prompt:

```
You are drafting a single cohesive unified diff to apply a set of validated
learnings to a target file.

Target file: {file_path}

Current file content:
<file>
{full content of file_path}
</file>

Validated learnings ({N} total):
{for each valid learning: id, problem, lesson, fix}

Instructions:
1. Read each learning's `fix` field carefully.
2. Synthesize all fixes into a single coherent edit. Think about how they
   interact and produce one unified improvement — not N independent edits.
3. Produce a standard unified diff (diff -u format) suitable for `patch -p0`.
4. Be minimal and surgical. Do not rewrite sections unrelated to the learnings.
5. Include 3 context lines before and after each change hunk.
6. Return ONLY the diff, starting with "--- " and ending after the last hunk.
   No prose, no explanation.
```

Store the returned diff.

## Step 6: User approval

Present the diff to the user:

```
Proposed changes to <file_path>
(<N> learnings: <comma-separated ids>)

<diff content>

Apply these changes? [y/n]
```

Wait for response.

- `n` or any rejection: Print "Changes rejected. No files modified." and jump to
  Step 8 (summary only — do not commit or mark applied).
- `y` or acceptance: Proceed to Step 7.

## Step 7: Apply and commit

Write the diff to a temp file and apply it:

```bash
PATCH_FILE="/tmp/improve-skill-learnings-<target>.patch"
# (write diff content to $PATCH_FILE via a Python write — not echo/heredoc)
python3 -c "
import sys
diff = '''<diff content>'''
with open('$PATCH_FILE', 'w') as f:
    f.write(diff)
"

patch -p0 < "$PATCH_FILE"
```

If `patch` exits non-zero, report the error and stop. Do not mark entries as
applied if the patch fails.

Mark all valid learnings as applied:

```bash
python3 ~/.dotfiles/claude-code-shared/scripts/update-learning.py \
  --id <id> --status applied
```

(Run once per valid learning — loop or run sequentially.)

Commit:

```bash
git add <file_path>
git commit -m "improve(<target>): apply <N> learnings"
```

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
  Acted:   N  — committed to <file_path>
  Stale:   N  — marked stale, skipped
  Invalid: N  — marked invalid (target file not resolvable), skipped

Remaining backlog (<M> total across all targets):
  <slug1>: N learnings
  <slug2>: N learnings
  ...
  (unassigned): N learnings
```

If the backlog is empty, print "Backlog clear — no remaining captured learnings."

<!-- learning-capture:start -->
Read and execute `~/.dotfiles/claude-code-shared/resources/learning-capture.md`.
This skill's slug is `improve-skill-learnings`.
<!-- skill-done: improve-skill-learnings -->
<!-- learning-capture:end -->
