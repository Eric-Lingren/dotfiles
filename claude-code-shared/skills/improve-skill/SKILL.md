---
name: improve-skill
description: >
  Self-improving skill evaluator. Runs a target skill against synthetic scenarios,
  scores output with 5-tier rubric via multi-judge LLM panel, and iteratively improves
  the skill through a learning loop. Also analyzes skill structure for optimization
  opportunities. Use when user says "improve skill", "eval skill", "run evals",
  "optimize skill", "self-improve", or invokes /improve-skill.
---

# Improve Skill

You are running an automated skill improvement loop. Follow this process exactly.

## Arguments

The user provides: `/improve-skill <skill-name>` with optional `--reset` flag.

Parse the skill name from ARGUMENTS. If `--reset` is present, delete the target skill's `evals/` directory before proceeding.

## Step 1: Locate the target skill

Search this directory for a folder matching `<skill-name>`:
`~/.dotfiles/claude-code-shared/skills/<skill-name>/SKILL.md`

If not found, tell the user and stop.

Read the target SKILL.md. Store its full contents for later use.

## Step 2: Check for existing evals

Run the scaffold script to check/create the evals directory:
`~/.dotfiles/claude-code-shared/skills/improve-skill/scripts/scaffold-evals.sh <target-skill-dir> [--reset]`

Then check for `<target-skill-dir>/evals/eval.json`.

- If it exists and `--reset` was NOT passed, skip to **Step 4**.
- Otherwise, proceed to **Step 3**.

## Step 3: Scaffold eval.json

This step creates the evaluation definition. Two phases.

### Phase A: Auto-generate from SKILL.md

Read the target SKILL.md and extract every concrete behavioral rule, constraint, or requirement. For each one, create a candidate assertion with a 5-tier rubric:

```json
{
  "name": "snake_case_short_name",
  "description": "Natural language description of what the output must demonstrate.",
  "rubric": {
    "0": "Concrete description of what a 0 score looks like",
    "25": "Concrete description of what a 25 score looks like",
    "50": "Concrete description of what a 50 score looks like",
    "75": "Concrete description of what a 75 score looks like",
    "100": "Concrete description of what a 100 score looks like"
  }
}
```

Each rubric tier must be specific and anchored to observable behavior. No vague language like "mostly" or "partially."

**Always include the 3 built-in consistency assertions.** Read them from `resources/builtin-assertions.md` in this skill's directory. The exact names are `number_consistency`, `no_contradictions`, `plan_cohesion`. Never rename or substitute them.

Also generate 5 synthetic scenarios. Each scenario should:
- Be a realistic task the skill would handle
- Vary in complexity (simple to complex)
- Cover different aspects of the skill's behavior

```json
{
  "name": "snake_case_scenario_name",
  "prompt": "The full prompt/task to give the skill",
  "context": "Optional setup context (language, framework, project type)"
}
```

### Phase B: Grill user on gaps

Present the auto-generated assertions and scenarios to the user. Ask exactly these 2 questions:

1. "Here are the assertions and rubrics I extracted. Any behaviors I missed? Any rubric anchors need adjustment?"
2. "Here are the 5 scenarios. Do these cover enough variety?"

Do not ask additional questions. Incorporate feedback, then write the final eval.json to `<target-skill-dir>/evals/eval.json`.

## Step 4: Run the improvement loop

Read these files:
- `<target-skill-dir>/SKILL.md` (current skill definition)
- `<target-skill-dir>/evals/eval.json` (scenarios + assertions)
- `<target-skill-dir>/evals/learnings.md` (if exists, prior learnings)
- `<target-skill-dir>/evals/scores.json` (if exists, prior scores)

Initialize iteration counter at 1. Max iterations: 3.

### For each iteration:

#### 4a: Execute skill against each scenario

For each scenario in eval.json, spawn an Agent (subagent_type: "general-purpose", model: "sonnet") with this prompt structure:

```
You are executing a skill. Follow the skill instructions below exactly.

## Skill Instructions
<contents of target SKILL.md>

## Learnings (apply these)
<contents of learnings.md, if any>

## Your Task
<scenario prompt and context>

Produce your full output as if you were executing this skill for a real user.
```

Capture the full text output from each subagent.

#### 4b: Score with multi-judge panel

For each (scenario, assertion) pair, spawn **3** Agents (subagent_type: "general-purpose", model: "haiku"). Use the judge prompt template from `examples/judge-prompt.md`.

**Aggregation:** Average the 3 judge scores, then snap to the nearest tier (0/25/50/75/100). Snap thresholds: 0-12 = 0, 13-37 = 25, 38-62 = 50, 63-87 = 75, 88-100 = 100. Collect any "reason" strings from judges that scored 0 or 25.

#### 4b-2: Consistency cross-check

After all per-assertion judges complete, spawn one Agent (subagent_type: "general-purpose", model: "sonnet") per scenario output. Use the consistency auditor prompt from `examples/consistency-auditor-prompt.md`.

#### 4c: Generate report

Build a report with:

1. **Header:** `Iteration N/3 - Score: X/100 - prev: Y/100`
   - Score = simple average of all snapped cell scores across all (scenario, assertion) pairs. No weighting.

2. **Matrix table:** A scenario x assertion grid showing individual cell tier scores.

3. **Failure details:** For each cell scoring 25 or below, include scenario name, assertion name, score, collected judge reasons, and a specific improvement suggestion.

4. **Low scores:** For each cell scoring 50, same format as failures.

#### 4d: Update learnings.md

For each cell scoring 50 or below, append a dated entry to `<target-skill-dir>/evals/learnings.md`:

```markdown
## <date> - Iteration <N>
- **<assertion_name>** [<score>]: <what went wrong and how to fix it>
```

#### 4e: Check for promotions

Review scores.json history. If any assertion has scored 25 or below in 2 consecutive iterations (current + previous, can span runs), promote the fix:

1. Read current SKILL.md
2. Identify where the improvement should be inserted
3. Edit SKILL.md to incorporate the fix
4. Remove the promoted learning from learnings.md

#### 4f: Prune stale learnings

Remove any learning entries older than 2 iterations that have not been associated with a low score in recent runs.

#### 4g: Check exit conditions

Exit conditions are strict. Apply them in order. Never override based on judgment.

- If average score >= 85, stop the loop immediately. Exit reason: "strong_score".
- If iteration >= 3 and score delta < 5 compared to previous iteration, stop. Exit reason: "plateau".
- If iteration counter reaches 3, stop. Exit reason: "max_iterations".
- Otherwise, increment iteration counter and repeat from 4a.

## Step 5: Structural analysis

After the eval loop completes, analyze the target skill's directory structure against this checklist. Each item is binary pass/fail.

### Checklist items (exactly these 5)

**1. Token weight:** Count tokens in SKILL.md + all referenced files. Pass if total <= 5000 tokens. Fail if over. Report the count.

**2. Inline knowledge extraction:** Scan SKILL.md for prose blocks over 200 words. Pass if none found. Fail if found. List candidates with suggested filenames.

**3. Example extraction:** Scan SKILL.md for inline code examples or sample outputs longer than 10 lines. Pass if none found. Fail if found.

**4. Missing resource files:** Identify concepts SKILL.md references 3+ times but never defines. Pass if none. Fail if found.

**5. Script candidates:** Identify deterministic steps (file scaffolding, directory creation, JSON validation, file listing/counting) that could be shell scripts. Pass if none. Fail if found.

### Structural score

Score = (items passed / 5) * 100. This score is independent of the behavioral score.

## Step 6: Write scores.json

Append the run result to `<target-skill-dir>/evals/scores.json`. See `examples/scores-json-schema.md` for the expected format.

## Step 7: Final report

Display results to the user with exactly these 8 sections:

1. **Run summary:** Start score, end score, iterations run, exit reason
2. **Score progression:** Each iteration's average score on one line
3. **Final matrix:** The last iteration's full scenario x assertion grid with tier scores
4. **Failure details:** From the last iteration, cells scoring 25 or below with suggestions
5. **Low scores:** Cells scoring 50 with suggestions
6. **Structural analysis:** Structural score (X/100), each checklist item pass/fail with detail, recommendations
7. **Changes made:** Learnings added, promotions made, learnings pruned
8. **Recommendation:** What to focus on next

## Important rules

- Run all iterations autonomously. Do not pause for user approval between iterations.
- Only pause during Step 3 (eval scaffolding) to get user input on assertions, rubrics, and scenarios.
- Use `model: "haiku"` for judge subagents to minimize token cost.
- Use `model: "sonnet"` for skill execution subagents for balanced quality/cost.
- Spawn all 3 judges for a cell in parallel.
- When editing SKILL.md for promotions, make minimal surgical changes. Do not rewrite the whole file.
- If learnings.md does not exist, create it on first write.
- If scores.json does not exist, create it with an empty `runs` array.
- Keep judge prompts minimal. The judge scores against rubric anchors only.
