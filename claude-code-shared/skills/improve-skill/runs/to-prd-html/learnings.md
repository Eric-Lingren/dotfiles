# Learnings: to-prd-html

## 2026-06-02 - Iteration 1

- **theme_applied_correctly** [50; minimal_context_prd]: With very minimal input ("add dark mode to dashboard"), skill simulations apply CSS vars inconsistently when work/personal choice hasn't been confirmed yet. The mandatory work/personal question MUST be asked before theming begins — if the prompt is ambiguous, the question is even more critical. No shortcutting.

- **content_sections_complete** [50; minimal_context_prd]: Minimal prompts produce thin implementation and testing sections. Skill must synthesize from the feature description itself — dark mode touches every themed component, so implementation should enumerate affected modules (CSS vars, component overrides, localStorage persistence), and testing should specify visual regression and OS preference detection tests.

- **json_quality** [50; minimal_context_prd]: For sparse input, success_metrics default to vague category labels. Fix: always anchor metrics to measurable numbers (e.g. "0 reported WCAG contrast failures post-launch", "dark mode persists across sessions for 100% of users who toggle it"). Evidence must be 1-2 sentences — enforce this even when input is thin.
