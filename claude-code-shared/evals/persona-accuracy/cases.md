# persona-accuracy cases

Expected: `clean` and `distractor` -> no accuracy refutation; `planted` -> a refutation on `field`.

| id | kind | type | field |
|---|---|---|---|
| ci-fix--clean | clean |  |  |
| improve-learnings--clean | clean |  |  |
| relay-posting--clean | planted | native-count | decisions[11] |
| ci-fix--drift-1 | planted | drift | decisions[3] |
| ci-fix--drift-2 | planted | drift | summary |
| ci-fix--stale-1 | planted | stale | decisions[12] |
| ci-fix--stale-2 | planted | stale | decisions[2] |
| ci-fix--scope-1 | planted | scope | decisions[10] |
| ci-fix--scope-2 | planted | scope | decisions[11] |
| ci-fix--negation-1 | planted | negation | decisions[9] |
| ci-fix--negation-2 | planted | negation | decisions[5] |
| ci-fix--distractor-1 | distractor | fabricated-rationale | decisions[7] |
| ci-fix--distractor-2 | distractor | fabricated-rationale | decisions[13] |
| improve-learnings--drift-1 | planted | drift | decisions[4] |
| improve-learnings--drift-2 | planted | drift | decisions[10] |
| improve-learnings--stale-1 | planted | stale | decisions[1] |
| improve-learnings--stale-2 | planted | stale | decisions[5] |
| improve-learnings--scope-1 | planted | scope | decisions[16] |
| improve-learnings--scope-2 | planted | scope | decisions[13] |
| improve-learnings--negation-1 | planted | negation | decisions[7] |
| improve-learnings--negation-2 | planted | negation | decisions[17] |
| improve-learnings--distractor-1 | distractor | fabricated-rationale | decisions[15] |
| improve-learnings--distractor-2 | distractor | fabricated-rationale | decisions[0] |
| relay-posting--drift-1 | planted | drift | decisions[6] |
| relay-posting--drift-2 | planted | drift | decisions[0] |
| relay-posting--stale-1 | planted | stale | decisions[1] |
| relay-posting--stale-2 | planted | stale | decisions[9] |
| relay-posting--scope-1 | planted | scope | decisions[8] |
| relay-posting--scope-2 | planted | scope | decisions[12] |
| relay-posting--negation-1 | planted | negation | decisions[4] |
| relay-posting--negation-2 | planted | negation | decisions[2] |
| relay-posting--distractor-1 | distractor | fabricated-rationale | decisions[13] |
| relay-posting--distractor-2 | distractor | fabricated-rationale | decisions[5] |

## ci-fix--drift-1

**planted / drift** in `decisions[3]`

- before: for user review after the fact.
- after: for user approval before pushing.
- transcript anchor: user: 'flag the semantic fixes ... so I can double check that and be aware of that after the fact.'

## ci-fix--drift-2

**planted / drift** in `summary`

- before: auto-fixes all failure types (lint, type errors, test failures, build config)
- after: auto-fixes mechanical failure types (lint, type errors)
- transcript anchor: user: 'I think I should auto fix all of them'

## ci-fix--stale-1

**planted / stale** in `decisions[12]`

- before: One shot per invocation. No auto-retry. User re-invokes manually if needed.
- after: Auto-retry with a 2-attempt cap: fix, push, poll CI, one more round if still red, then stop and report.
- transcript anchor: user answered Q13 'b' (auto-retry), then: 'Actually back to question thirteen. Let's actually do a let's do one shot.'

## ci-fix--stale-2

**planted / stale** in `decisions[2]`

- before: Repo gating uses repo-policy.json CI field (e.g. ci: {provider: circleci, project_slug: gh/Quaestor-Technologies/Quaestor-Web}), falling back to .circleci/config.yml detection.
- after: Repo gating detects .circleci/config.yml dynamically and resolves the project slug from the git remote.
- transcript anchor: user picked Q3 option B (dynamic detect), then pointed at repo-policy.json; assistant: 'Revised answer on Q3: Use both. Add a ci field to repo-policy.json ... Falls back to .circleci/config.yml'

## ci-fix--scope-1

**planted / scope** in `decisions[10]`

- before: Fix all failing jobs in one pass.
- after: Fix all failing jobs across all open branches in one pass.
- transcript anchor: user: 'I'm always gonna be on a work tree in a specific branch ... no reason ... to run a CI check on a different branch'

## ci-fix--scope-2

**planted / scope** in `decisions[11]`

- before: Load CircleCI MCP debug-failing-run playbook via list_skills + get_skill
- after: Load all CircleCI MCP playbooks via list_skills + get_skill
- transcript anchor: assistant recap: 'MCP playbooks: Load CircleCI's debug-failing-run skill.'

## ci-fix--negation-1

**planted / negation** in `decisions[9]`

- before: Stop and report if local verification fails. Never push broken code.
- after: Push anyway and report if local verification fails.
- transcript anchor: assistant recap: 'Push behavior: Auto-push via gxpush --auto. Stop if local verification fails.'

## ci-fix--negation-2

**planted / negation** in `decisions[5]`

- before: CircleCI MCP auth is hard-required. Skill refuses to run if not authenticated, tells user to /mcp and select CircleCI.
- after: CircleCI MCP auth is not required. Skill falls back to the gh CLI when not authenticated.
- transcript anchor: Q6 A = hard require, user answered 'a'; recap: 'MCP auth: Hard require.'

## ci-fix--distractor-1

**distractor / fabricated-rationale** in `decisions[7]`

- before: Skill name: /ci-fix, slug: ci-fix.
- after: Skill name: /ci-fix, slug: ci-fix, chosen to mirror the existing /pr-fix skill name.
- transcript anchor: no rationale for the name was discussed (Grounding lens, not Accuracy)

## ci-fix--distractor-2

**distractor / fabricated-rationale** in `decisions[13]`

- before: Standard repo convention.
- after: Standard repo convention, adopted after a commit-lint incident last quarter.
- transcript anchor: no incident discussed (Grounding lens, not Accuracy)

## improve-learnings--drift-1

**planted / drift** in `decisions[4]`

- before: (both confirmed and candidate confidence levels)
- after: (confirmed confidence level only)
- transcript anchor: Q5 B = 'All captured: act on both confirmed and candidate'; user: 'b. but we shoudl have some verrifiation'

## improve-learnings--drift-2

**planted / drift** in `decisions[10]`

- before: Verification is diff review only. No automated benchmark run
- after: Verification defaults to diff review; an automated benchmark run is optional
- transcript anchor: verification Q: B = 'Dry-run + diff review ... No automated verification'; user: 'b'

## improve-learnings--stale-1

**planted / stale** in `decisions[1]`

- before: improve-skill-benchmarks (rename of current improve-skill) + improve-skill-learnings (new)
- after: improve-skill-eval (rename of current improve-skill) + improve-skill-learn (new)
- transcript anchor: user: 'improve-skill-eval is better but its not clear...' then 'improve-skill-benchmarks and improve-skill-learnings i think are the ones.'

## improve-learnings--stale-2

**planted / stale** in `decisions[5]`

- before: Validation via Haiku agent per learning
- after: Validation via the investigate skill per learning
- transcript anchor: user: 'mayer we can us the invesitage skill?' then after options: 'ok, we can do c' (inline Haiku agent)

## improve-learnings--scope-1

**planted / scope** in `decisions[16]`

- before: Update learning-schema.json to add
- after: Update learning-schema.json and every other contract schema to add
- transcript anchor: status enum change discussed for the learnings schema only

## improve-learnings--scope-2

**planted / scope** in `decisions[13]`

- before: searches skills/, agents/, resources/, scripts/ directories
- after: searches the entire repository and every installed plugin
- transcript anchor: file resolution scoped to the skills/agents/resources/scripts dirs

## improve-learnings--negation-1

**planted / negation** in `decisions[7]`

- before: stale/invalid/applied never re-investigated
- after: stale/invalid entries are re-investigated on every run
- transcript anchor: user: 'if its been marked invalid/stale, we dont need to reinvestigate those each run'

## improve-learnings--negation-2

**planted / negation** in `decisions[17]`

- before: is bundled with this work, not deferred
- after: is deferred to a follow-up, not bundled with this work
- transcript anchor: user: 'bundle'

## improve-learnings--distractor-1

**distractor / fabricated-rationale** in `decisions[15]`

- before: Atomic rewrite with fcntl.flock like log-learning.py
- after: Atomic rewrite with fcntl.flock like log-learning.py, chosen after a past corruption of the learnings file
- transcript anchor: no corruption incident discussed (Grounding lens)

## improve-learnings--distractor-2

**distractor / fabricated-rationale** in `decisions[0]`

- before: Standalone new skill, not an extension of improve-skill
- after: Standalone new skill, not an extension of improve-skill, because improve-skill's judge panel is too slow for this use
- transcript anchor: no speed rationale discussed (Grounding lens)

## relay-posting--drift-1

**planted / drift** in `decisions[6]`

- before: Can be collapsed to single-step later once proven reliable.
- after: Will be collapsed to single-step after the first release.
- transcript anchor: user: 'double . we can remove the extra confrimation later if this is proven reliabel'

## relay-posting--drift-2

**planted / drift** in `decisions[0]`

- before: Linear and Slack adapters remain copy-only stubs.
- after: Linear and Slack adapters are removed.
- transcript anchor: user: 'github only for now. ev erything else shodul reamin stub and inline copy only'

## relay-posting--stale-1

**planted / stale** in `decisions[1]`

- before: Use gh api (REST) for GitHub posting. Covers both flat PR comments and inline review thread replies via in_reply_to.
- after: Use gh pr comment for GitHub posting.
- transcript anchor: gh pr comment vs gh api compared first; then 'So gh pr comment won't work for inline threads ... Updated decision: gh api'

## relay-posting--stale-2

**planted / stale** in `decisions[9]`

- before: Add thread_database_id field to carry REST numeric comment id alongside GraphQL node id.
- after: Resolve the GraphQL node id to a REST comment id via gh api /graphql at post time. No new field.
- transcript anchor: Q10 rec resolved via /graphql; superseded after harvest check: user 'add thread_database_id, keep both'

## relay-posting--scope-1

**planted / scope** in `decisions[8]`

- before: Remove never clauses and stub banner from post-github only.
- after: Remove never clauses and stub banner from all post-* adapters.
- transcript anchor: 'Remove the never clauses and stub banner from post-github only ... Keep the never clauses in post-linear and post-slack'

## relay-posting--scope-2

**planted / scope** in `decisions[12]`

- before: (copy new fields to reply task)
- after: (copy new fields to every task type)
- transcript anchor: new fields are on reply tasks only

## relay-posting--negation-1

**planted / negation** in `decisions[4]`

- before: Posted comment contains draft text only. Original comment is shown only during HITL review, not repeated in the GitHub post.
- after: Posted comment quotes the original comment above the draft text in the GitHub post.
- transcript anchor: user: 'A, draft only'

## relay-posting--negation-2

**planted / negation** in `decisions[2]`

- before: Embed original comment body at task creation time in pr-revise harvest, not fetched at relay time.
- after: Fetch original comment body at relay time, not embedded at task creation.
- transcript anchor: user: 'B, embed at task creation'

## relay-posting--distractor-1

**distractor / fabricated-rationale** in `decisions[13]`

- before: No additional MCP or write tools needed.
- after: No additional MCP or write tools needed, matching the post-linear permission set.
- transcript anchor: no permission-set comparison discussed (Grounding lens)

## relay-posting--distractor-2

**distractor / fabricated-rationale** in `decisions[5]`

- before: original_comment_author (string).
- after: original_comment_author (string), named to match GitHub's GraphQL field names.
- transcript anchor: no naming rationale discussed (Grounding lens)
