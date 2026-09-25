## 2026-06-02 - Iteration 1

- **prd_file_selection** [50]: When user provides a PRD path directly in their prompt, skill accepts it and proceeds without listing other available files in docs/prd/ or explicitly asking for confirmation. Skill should still list available files and require explicit user selection even when a path is mentioned inline.

- **vertical_slice_quality** [50]: In the no_prd_conversation_context scenario, skill correctly refused to generate tasks (per spec: no PRD = direct to /to-prd). Score of 50 reflects N/A scoring, not a real failure. Note: the skill has a gap — it cannot accept inline conversation context as a PRD source, forcing users back to /to-prd even when context is fully available.

- **test_coverage_requirement** [50]: Same N/A condition as above. Scored 50 because no tasks were generated, not because test criteria were missing.

- **task_json_schema** [50]: Same N/A condition as above. No JSON produced because skill correctly refused. Also noted: complex_multi_service scenario revealed the skill's branching field shape for multi-branch strategy is ambiguous — SKILL.md illustrative schema shows a single `branch` string but multi-branch scenarios need an array or different shape. The skill should clarify how to represent multi-branch in the JSON output.
