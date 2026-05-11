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

Look for `<target-skill-dir>/evals/eval.json`.

- If it exists and `--reset` was NOT passed, skip to **Step 4**.
- Otherwise, proceed to **Step 3**.

## Step 3: Scaffold eval.json

This step creates the evaluation definition. Two phases.

### Phase A: Auto-generate from SKILL.md

Read the target SKILL.md and extract every concrete behavioral rule, constraint, or requirement. For each one, create a candidate assertion with a 5-tier rubric:

```json
{
  "name": "snake_case_short_name",
  "description": "Natural language description of what the output must demonstrate. Written as a statement the judge evaluates.",
  "rubric": {
    "0": "Concrete description of what a 0 score looks like for this assertion",
    "25": "Concrete description of what a 25 score looks like",
    "50": "Concrete description of what a 50 score looks like",
    "75": "Concrete description of what a 75 score looks like",
    "100": "Concrete description of what a 100 score looks like"
  }
}
```

Each rubric tier must be specific and anchored to observable behavior. No vague language like "mostly" or "partially." Describe what the output actually contains or lacks at each tier.

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

Present the auto-generated assertions and scenarios to the user. Ask:

1. "Here are the assertions and rubrics I extracted. Any behaviors I missed? Any rubric anchors need adjustment?"
2. "Here are the 5 scenarios. Do these cover enough variety?"

Incorporate feedback. Then write the final eval.json:

```json
{
  "skill": "<skill-name>",
  "scenarios": [ ... ],
  "assertions": [ ... ]
}
```

Write to `<target-skill-dir>/evals/eval.json`.

## Step 4: Run the improvement loop

Read these files:
- `<target-skill-dir>/SKILL.md` (current skill definition)
- `<target-skill-dir>/evals/eval.json` (scenarios + assertions)
- `<target-skill-dir>/evals/learnings.md` (if exists, prior learnings)
- `<target-skill-dir>/evals/scores.json` (if exists, prior scores)

Initialize iteration counter at 1. Max iterations: 5.

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

For each (scenario, assertion) pair, spawn **3** Agents (subagent_type: "general-purpose", model: "haiku") with this prompt:

```
You are a judge. Score the output against this assertion.

## Output
<captured output from step 4a>

## Assertion
<assertion description>

## Rubric
0: <rubric anchor for 0>
25: <rubric anchor for 25>
50: <rubric anchor for 50>
75: <rubric anchor for 75>
100: <rubric anchor for 100>

Reply ONLY with JSON: {"score": <0|25|50|75|100>}
Failing scores (0 or 25) MUST include "reason": "one sentence"
```

**Aggregation:** Average the 3 judge scores, then snap to the nearest tier (0/25/50/75/100). Snap thresholds: 0-12 → 0, 13-37 → 25, 38-62 → 50, 63-87 → 75, 88-100 → 100. Collect any "reason" strings from judges that scored 0 or 25.

#### 4c: Generate report

Build a report with:

1. **Header:** `Iteration N/5 - Score: X/100 - prev: Y/100`
   - Score = simple average of all snapped cell scores across all (scenario, assertion) pairs.

2. **Matrix table:**
```
                        | assertion_1 | assertion_2 | assertion_3
scenario_1              |     75      |      0      |     100
scenario_2              |     50      |     75      |      25
```

3. **Failure details:** For each cell scoring 25 or below:
```
FAILED: <scenario> x <assertion> [<score>]
  Reason: <collected judge reasons>
  Suggestion: <specific improvement to the skill instructions that would fix this>
```

4. **Low scores:** For each cell scoring 50:
```
LOW: <scenario> x <assertion> [50]
  Reason: <collected judge reasons if any>
  Suggestion: <improvement suggestion>
```

Generate suggestions by analyzing what the skill instructions lack or state unclearly that caused the score.

#### 4d: Update learnings.md

For each cell scoring 50 or below, append a dated entry to `<target-skill-dir>/evals/learnings.md`:

```markdown
## <date> - Iteration <N>
- **<assertion_name>** [<score>]: <what went wrong and how to fix it>
```

#### 4e: Check for promotions

Review scores.json history. If any assertion has scored 25 or below in 2 consecutive iterations (current + previous), promote the fix:

1. Read current SKILL.md
2. Identify where the improvement should be inserted
3. Edit SKILL.md to incorporate the fix
4. Remove the promoted learning from learnings.md

#### 4f: Prune stale learnings

Remove any learning entries older than 3 iterations that have not been associated with a low score in recent runs.

#### 4g: Check exit conditions

- If average score >= 85, stop the loop. Exit reason: "strong_score".
- If score delta < 5 compared to previous iteration, stop the loop. Exit reason: "plateau".
- If iteration counter reaches 5, stop the loop. Exit reason: "max_iterations".
- Otherwise, increment iteration counter and repeat from 4a.

## Step 5: Structural analysis

After the eval loop completes, analyze the target skill's directory structure against this checklist. Each item is binary pass/fail.

### Checklist items

**1. Token weight:** Count tokens in SKILL.md + all referenced/linked files in the skill directory. Pass if total <= 5000 tokens. Fail if over. Report the count and suggest what to trim or extract.

**2. Inline knowledge extraction:** Scan SKILL.md for prose blocks over 200 words that explain a concept, methodology, or domain knowledge. These are candidates for extraction into separate resource files (like `mocking.md`, `deep-modules.md`). Pass if no large extractable blocks. Fail if blocks found. List each candidate with suggested filename.

**3. Example extraction:** Scan SKILL.md for inline code examples or sample outputs longer than 10 lines. These could move to an `examples/` directory, loaded on demand. Pass if no large inline examples. Fail if found.

**4. Missing resource files:** Identify concepts SKILL.md references repeatedly (3+ times) but never defines in detail. These are candidates for a dedicated resource `.md` file. Pass if no missing resources detected. Fail if found.

**5. Script candidates:** Identify deterministic steps in the skill (file scaffolding, directory creation, JSON schema validation, file listing/counting) that could be shell scripts instead of LLM reasoning. Pass if no script candidates. Fail if found.

### Structural score

Score = (items passed / 5) * 100. This score is independent of the behavioral score.

## Step 6: Write scores.json

Append the run result to `<target-skill-dir>/evals/scores.json`:

```json
{
  "runs": [
    {
      "timestamp": "<ISO 8601>",
      "iterations": "<count>",
      "exit_reason": "strong_score|plateau|max_iterations",
      "behavioral_score": 82,
      "structural_score": 60,
      "scores": [
        {
          "iteration": 1,
          "total_cells": 15,
          "average_score": 58,
          "cell_scores": [
            {
              "scenario": "...",
              "assertion": "...",
              "score": 75,
              "judge_scores": [75, 75, 50],
              "reason": "null or failure reason"
            }
          ]
        }
      ],
      "structural_recommendations": [
        {
          "item": "token_weight",
          "pass": false,
          "detail": "5.2k tokens total, over 5k threshold. Extract examples to reduce by ~800 tokens."
        }
      ],
      "promotions": ["list of assertions promoted to SKILL.md"],
      "learnings_added": 3,
      "learnings_pruned": 1
    }
  ]
}
```

## Step 7: Final report

Display the complete results to the user:

1. **Run summary:** Start score → end score, iterations run, exit reason
2. **Score progression:** List each iteration's average score on one line
3. **Final matrix:** The last iteration's full matrix with tier scores
4. **Failure details:** From the last iteration, cells scoring 25 or below with suggestions
5. **Low scores:** Cells scoring 50 with suggestions
6. **Structural analysis:**
   - Structural score (X/100)
   - Each checklist item: pass/fail with detail
   - Actionable recommendations
7. **Changes made:**
   - Learnings added to learnings.md
   - Promotions made to SKILL.md (if any)
   - Learnings pruned (if any)
8. **Recommendation:** What to focus on next to keep improving

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
