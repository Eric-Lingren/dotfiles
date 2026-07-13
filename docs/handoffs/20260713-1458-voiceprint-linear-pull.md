# Handoff: Voiceprint — Linear corpus pull and profile update

**Source ref:** `20260713-1427-voiceprint-voice-corpus.json`

## What this is

Eric wants his own writing tone captured into a voice profile that AI writing
agents can use so their output sounds like him (direct, informal) instead of
generic AI prose (formal, hedgy). The GitHub half of this is already done.
This handoff is for the remaining Linear half.

## What's already done

- `docs/voice-profile.md` exists in this repo (public `~/.dotfiles`), built
  entirely from Eric's GitHub PR/review comments (Quaestor-Technologies org).
  Two layers: paste-ready imperative rules, then an evidenced profile across
  7 dimensions. Not yet committed to git.
- Full detail on what was tried, what got blocked, and why is in
  `docs/tasks/20260713-1427-voiceprint-voice-corpus.json` — read task
  summaries for T-0083 through T-0086 before doing anything. Don't
  re-derive this from scratch; it's already written up there.

## The load-bearing constraint (read this first)

Partway through the original run, Claude Code's auto-mode classifier
hard-blocked a script that was bulk-pulling verbatim company PR/review
comments (including code blocks) from Eric's employer's GitHub org and
writing them into a personal repo intended for push. It flagged this as a
data-exfiltration pattern regardless of stated user intent.

The resolution Eric chose applies to Linear too, since Linear comments also
reference internal company work:

- **Never persist raw pulled comment text to any file**, transient in-memory
  processing only (or a scratchpad file deleted immediately after use).
- **Paraphrase, don't quote verbatim**, when writing into `voice-profile.md`.
  No code blocks, no direct issue/comment links back to the company's Linear
  workspace, no coworker names, genericize everything.
- Output lands only in `docs/voice-profile.md` in this public dotfiles repo,
  there is no separate private corpus repo anymore (a `~/.voiceprint` repo
  was created for that purpose, then abandoned and deleted mid-run — don't
  recreate it).

If in doubt about whether something is "verbatim enough" to be a concern, err
towards paraphrasing more.

## What's blocking Linear specifically

No Linear access existed in that session: no MCP server, no API key, no CLI.
Eric said he'd authenticate before spinning up this next agent, check
whether that's done (env var, keychain entry, or explicit key he provides at
session start) before assuming access still doesn't exist.

## What to actually do

1. Confirm Linear access works (however Eric set it up).
2. Pull Eric's authored Linear issue comments, scoped the same way the seed
   originally specified: all teams/issues he has access to, no time ceiling,
   comments only (not descriptions).
3. Do not write raw comments to any file. Process transiently and go
   straight to paraphrased dimension-level observations.
4. Read the existing `docs/voice-profile.md` and fold Linear-derived signal
   into it in place (don't overwrite the GitHub-derived content, extend it —
   same 7 dimensions, same paste-ready rule block, update rule count/wording
   if Linear reveals something GitHub didn't).
5. Update `docs/tasks/20260713-1427-voiceprint-voice-corpus.json`: flip
   T-0085 from `blocked` to `done` with an accurate summary, and update
   T-0086's summary to note Linear signal was folded in. Re-validate against
   schema after editing:
   ```bash
   bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
     --instance ~/.dotfiles/claude-code-shared/contracts/task-schema.json \
     docs/tasks/20260713-1427-voiceprint-voice-corpus.json
   ```
6. Do this work directly in-session (like the GitHub pull was done), not
   through `/dispatch-tasks` → `build-code`. That pipeline assumes a
   TDD-testable codebase; this is data-gathering/authoring work with no test
   suite to drive. Going through it would just cause confusion, not add
   safety.

## Known loose ends (not blocking, mention if relevant)

- `~/.voiceprint` local dir may still exist if Eric hasn't run `rm -rf
  ~/.voiceprint` himself yet (sandboxed delete was blocked by a hook last
  session).
- The remote GitHub repo `Eric-Lingren/voiceprint` may still exist; deleting
  it needs `gh auth refresh -h github.com -s delete_repo` (browser consent)
  then `gh repo delete Eric-Lingren/voiceprint --yes`. Both are tracked as
  FU-001/FU-002 in the task file's `follow_ups`.
- `docs/voice-profile.md` has not been committed to git yet.

## Suggested skills

- No `/to-tasks` or `/to-seed` needed here, the task file already exists and
  covers this scope (T-0085/T-0086). Just do the work and update it directly.
- `/clean-scaffolding` once this and the git commit are done, to archive the
  seed/task chain.
