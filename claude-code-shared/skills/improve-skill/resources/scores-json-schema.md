# scores.json Schema

Append each run result to the `runs` array:

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
