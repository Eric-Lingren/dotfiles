---
name: improve-skill-learnings
description: >
  Apply captured learnings from unified-learnings.jsonl to their target skill,
  agent, process, or contract files. Shows a ranked table of targets, lets the
  user pick one or "run all" (offered when TOTAL ≤ 10). A picked target with
  ≤ 10 learnings also offers "run all" for that target. Validation is lazy —
  runs per-learning just before drafting, not upfront in batch. Run-all loops
  through every target and learning automatically with a y/n per diff. Covers
  all four improves_type values: skill, agent, process, contract.
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

## Step 2: User selects target (or "run all")

Ask the user which target they want to improve. Accept a rank number or a slug
name. Wait for the response.

**Run-all option:** When `TOTAL ≤ 10`, include a "Run all (N learnings)" option.
When selected, set `run_all = true` and skip to **Run-all mode** below — no
further target selection prompts appear.

If you use AskUserQuestion, pass at most 4 options (the tool maximum). When
run-all is offered, it takes one slot (pass it first). Pass the top 3 targets
in the remaining slots. Lower-ranked targets stay reachable via the built-in
"Other" free-text option.

Collect all captured entries for the selected target (by their `id` values from
step 1).

### Run-all mode

When `run_all = true`:

1. Work through targets in rank order. Skip `__unassigned__` targets unless
   that is the only one.
2. For each target, print a progress header:
   `--- Target <X>/<Y>: <slug> (<N> learnings) ---`
3. Iterate through the target's learnings using the pick-one loop (Steps 5–7).
   Lazy per-learning validation (Step 4) still applies — each learning is
   validated when it comes up in the loop, not upfront.
4. After all learnings for a target are exhausted (applied, skipped, or
   discarded), advance to the next target automatically. No prompt between
   targets.
   A learning retargeted mid-pass to a target outside the original rank list
   is deferred to the next run-all pass. Include it now only if the user
   explicitly asks.
5. After all targets are done, go to Step 8 (summary).

## Step 3: Fetch entry fields (no upfront validation)

Skip batch validation. Each learning is validated lazily in Step 4 when the
user selects it. This keeps parallel agent output out of the session context.

Step 1 prints only IDs. Fetch the full fields for the target's captured
entries. Set `TARGET` to the selected slug (`__unassigned__` for unassigned).
In run-all mode, rerun this for each target.

```bash
TARGET='<slug>' python3 - <<'PYEOF'
import json, os

target = os.environ["TARGET"]
path = os.path.expanduser(
    "~/.dotfiles/claude-code-shared/learnings/unified-learnings.jsonl"
)
keys = ("id", "improves", "improves_type", "reported_by", "problem", "lesson", "fix")
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            if e.get("status", "captured") != "captured":
                continue
            if (e.get("improves") or "__unassigned__") != target:
                continue
            print(json.dumps({k: e.get(k) for k in keys}))
except FileNotFoundError:
    pass
PYEOF
```

Each output line is one entry. This output is the only source of entry fields.
Step 5 shows `problem` from it. Step 4 and Step 6 fill `{id}`, `{improves}`,
`{improves_type}`, `{problem}`, `{lesson}` and `{fix}` verbatim from it. Never
paraphrase them. Never compose them from memory. If an entry is missing from
the output, rerun this step before dispatching any agent.

Then go to Step 5.

## Step 4: Validate one learning (lazy — called per pick from Step 5)

Spawn ONE Haiku validation agent for the selected learning. Build `path_candidates`
based on `improves_type`:

| improves_type | Paths to check (in order) |
|---------------|--------------------------|
| `skill`       | `~/.dotfiles/claude-code-shared/skills/<improves>/SKILL.md` |
| `agent`       | First hit of `find ~/.dotfiles/claude-code-shared/agents -name '<improves>.md'`, else `~/.dotfiles/claude-code-shared/agents/<improves>.md` |
| `process`     | `~/.dotfiles/claude-code-shared/resources/<improves>.md`, then `~/.dotfiles/claude-code-shared/resources/<improves>.json` |
| `contract`    | `~/.dotfiles/claude-code-shared/contracts/<improves>.json`, then `~/.dotfiles/claude-code-shared/contracts/<improves>.md` |

After the declared type's paths, append the other three types' paths (same
slug) as fallback candidates, in table order.

Resolve the `agent` row with the recursive find every time it is used. Agent
files can be nested (e.g. `agents/seed-review/<improves>.md`). The flat path alone
misses them.

**Unassigned entries (`improves` is null):** Use `reported_by` as the slug.
List all four types' paths for it, in table order. If `reported_by` is also
null, pass an empty list. These paths are a starting point only. The
validator greps for the real owner. Do not add custom rules to the prompt.

Pass this prompt to the Haiku agent (model: haiku). Fill the learning entry
fields verbatim from the Step 3 fetch output:

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
   If {improves} is null, skip the rest of this step. The paths come from the
   reporter, not an owner. If none exist, go to step 5.
   If none exist → return {"id": "{id}", "verdict": "invalid", "reason": "file_not_found", "file_path": null}
   If the first existing path belongs to a different type than {improves_type} →
   return {"id": "{id}", "verdict": "misrouted", "reason": "type_mismatch", "file_path": "<path>", "suggested_improves": "{improves}", "suggested_improves_type": "<type of that path>"}
2. Read the first file that exists (Read tool).
3. Does the file ALREADY contain the substance of the fix or lesson?
   If yes → return {"id": "{id}", "verdict": "stale", "reason": "already_applied", "file_path": "<path>"}
   Also check for partial coverage. The file may hold the core lesson but omit
   one dimension (a trigger, scenario, or criterion). If so → return
   {"id": "{id}", "verdict": "partial", "reason": "partial_coverage", "file_path": "<path>",
   "existing_line": <line number of the existing coverage>, "missing": "<the omitted dimension>"}
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
   Before returning misrouted in step 4 or 5, read the suggested owner's file and
   confirm it performs the action itself. A name in the fix text is not proof of
   ownership. If the owner only delegates, do not return misrouted; go to step 6.
6. Has the file changed so significantly that the lesson is no longer relevant?
   If yes → return {"id": "{id}", "verdict": "stale", "reason": "no_longer_relevant", "file_path": "<path>"}
7. Does the fix contradict a shared managed resource the target is meant to
   follow? Such resources include files the target pulls in by a managed marker
   block (e.g. `<!-- learning-capture:start -->
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
