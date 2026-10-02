# v1: output-contract fix (direct, no analyzer)

Hypothesis: the persona ignores the output contract. Baseline format_ok 0/99 (prose preamble or code fence on every reply), quote_ok 19% (spans wrapped as `User at line 43: "..."`, `[user: a]` splices, elisions), field_ok 83% (line numbers used as the decisions index). Source: the eval-build handoff's high-priority targets.

Change: (1) output rule restated as "first char `[`, last char `]`" with three concrete wrong examples and a note that the doc's fenced example is display-only; (2) `transcript_span` defined as an exact contiguous substring of one transcript message, listing the forbidden wrappers/edits and the JSON-escape trap; (3) `field` defined as a zero-based JSON path, never a line number.

Expected: format_ok and quote_ok up sharply; correct flat (grader parses leniently). Risk: tighter quoting could make the persona drop refutations it can't quote cleanly (watch recall).
