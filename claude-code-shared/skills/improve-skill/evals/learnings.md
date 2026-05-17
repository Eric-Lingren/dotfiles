# Learnings

## 2026-05-17 - Iteration 1

- **builtin_assertions_included** [0]: Execution agents substitute custom consistency assertions (e.g., "Run-to-run stability", "Format consistency") instead of the 3 spec'd built-in assertions. SKILL.md must emphasize that the built-in assertions are EXACTLY `number_consistency`, `no_contradictions`, `plan_cohesion` with the EXACT rubrics provided. Never rename or replace them.

- **structural_analysis** [0-50]: Execution agents perform informal structural observations instead of the 5 specific checklist items. SKILL.md must emphasize: the 5 items are (1) token weight <=5000, (2) inline knowledge >200 word blocks, (3) example extraction >10 line examples, (4) missing resource files with 3+ references, (5) script candidates. Each item is binary pass/fail. Structural score = (passed/5)*100.

- **report_format** [25-50]: Final reports use ad-hoc section structures instead of the 8 required sections. SKILL.md must list the 8 sections explicitly: (1) run summary, (2) score progression, (3) final matrix (scenario x assertion grid with tier scores), (4) failure details (cells <=25), (5) low scores (cells =50), (6) structural analysis, (7) changes made, (8) recommendation.

- **score_aggregation** [25]: One execution agent used a 70/30 weighting scheme instead of simple average. SKILL.md must emphasize: score = simple average of ALL snapped cell scores. Snap thresholds: 0-12->0, 13-37->25, 38-62->50, 63-87->75, 88-100->100. No weighting.

- **exit_conditions** [50]: One execution agent continued iterating past strong_score threshold (96.6 >= 85) based on subjective judgment. SKILL.md must clarify: exit conditions are STRICT. If avg >= 85, stop immediately with exit_reason "strong_score". Do not override.

- **user_grilling** [50]: One execution agent asked 5 custom questions instead of the 2 required questions. The 2 required questions are: (1) "Any behaviors I missed? Any rubric anchors need adjustment?" (2) "Do these cover enough variety?"
