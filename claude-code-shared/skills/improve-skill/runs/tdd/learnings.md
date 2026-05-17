# TDD Skill Learnings

## 2026-05-09 - Iteration 1
- **run_tests_after_refactor**: Skill output must explicitly state "ran tests" or "all tests pass" after each refactor step. The refactor section should include a clear test verification statement, not just describe the refactoring changes.
- **vertical_slices**: When presenting RED-GREEN cycles, show the granular sequence clearly: "wrote test X → test fails → wrote impl → test passes" for each cycle. Don't just summarize completed cycles in a table without showing the sequential flow.
- **test_behavior_not_implementation**: Avoid language like "Forces method X to exist" when describing what a test does. Instead describe the observable behavior being tested. E.g. "verifies order can transition from draft to submitted" not "forces transition() method to exist."
- **planning_phase**: Planning step must explicitly ask the user for confirmation before writing any code. Include a prompt like "Does this plan look right? Which behaviors should we prioritize?" Don't just list behaviors silently.
- **tracer_bullet_first**: For refactoring scenarios, the first test should still be a single tracer bullet that proves the end-to-end extraction works. Don't jump into testing individual validation methods without first proving the overall pattern works.
