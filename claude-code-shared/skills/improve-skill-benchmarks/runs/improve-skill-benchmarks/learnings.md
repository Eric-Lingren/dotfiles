# Learnings

## 2026-05-17 - Iteration 1 (partial — stale entries pruned 2026-06-01)

- **builtin_assertions_included** [0]: Execution agents substitute custom consistency assertions instead of the 3 spec'd built-in assertions. SKILL.md must emphasize that the built-in assertions are EXACTLY `number_consistency`, `no_contradictions`, `plan_cohesion` with the EXACT rubrics provided. Never rename or replace them. When the target skill has domain-specific context, do NOT adapt the built-in rubrics — copy the exact text from resources/builtin-assertions.md verbatim.

- **score_aggregation** [25]: One execution agent used a 70/30 weighting scheme instead of simple average. SKILL.md must emphasize: score = simple average of ALL snapped cell scores. Snap thresholds: 0-12->0, 13-37->25, 38-62->50, 63-87->75, 88-100->100. No weighting. Also: always collect and show failure reason strings from all judges who scored 0 or 25 — do not skip even when the cause seems obvious from the scenario description.

## 2026-06-01 - Iteration 1

- **number_consistency** [25] (existing_evals_skip): Score stated as 86 in the iteration header and 90 in the body calculation for the same iteration — two different numbers for the same result. Skill must compute the iteration score exactly once using the simple average of all snapped cell scores, state it in one place, and not introduce alternative calculation methods (e.g., "snapping row means then averaging") that produce a different number.

- **no_contradictions** [25] (existing_evals_skip): Header and body contradict each other (86 vs 90 for the same iteration's final score). Skill must derive the score via one consistent formula per spec and use that single number in both the iteration header and the body calculation sections.

- **builtin_assertions_included** [50] (complex_skill_many_rules): Built-in assertion rubrics adapted to domain context (e.g., "Summary count differs from listed count by 3+") instead of using the spec's generic rubric text ("Multiple numeric contradictions: stated counts don't match actual counts, step numbers skip or repeat…"). Always copy the EXACT rubric descriptions from resources/builtin-assertions.md verbatim.

- **number_consistency** [25] (promotion_trigger): Cell sum stated as 1530 but actual sum of the listed addends is 1700; stated average 51.0 is therefore also wrong (correct: 56.67). Skill must verify arithmetic by summing each addend explicitly before reporting the total — do not rely on mental arithmetic for cell-sum calculations.

- **score_aggregation / no_contradictions** [50] (promotion_trigger): Judge failure reasons not collected for rollback_plan cells scoring 0; arithmetic error in cell sum creates internal tension. Spec requires showing reason strings from all 0/25-scored judge calls. Verify all arithmetic before stating totals.
