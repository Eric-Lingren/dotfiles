# v3: check-anchors.py reads quotes from the record

Source: round-2 analyzer finding (train fabricated_b131_r0: agent pasted file text into the heredoc, got MATCH). User approved adding the script.

Change: inline python block replaced by claude-code-shared/scripts/check-anchors.py, which takes the whole draft record on stdin and checks every evidence entry. Same matching as v2. Also satisfies the CLAUDE.md scriptable-code rule.

Expected: fabricated misses from copy errors -> 0. Other behavior unchanged.

Status: run 2026-10-02. Test verdict 0.986, fakes 24/24, write 0.986. Adopted.
