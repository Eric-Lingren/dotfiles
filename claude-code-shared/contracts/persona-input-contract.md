---
name: persona-input-contract
description: Contract defining the input the orchestrator must provide to each adversary persona and judge agent during the to-seed verification stage.
---

# Persona and Judge Input Contract

**Producer:** to-seed verification stage orchestrator
**Consumer:** persona-grounding, persona-accuracy, persona-completeness, persona-coherence, persona-judge

## Persona input (all 4 adversary personas)

The orchestrator must pass the following as the agent prompt:

```
## Seed

seed_path: <absolute path to the seed JSON file produced in step 3a>

## Transcript

transcript_path: <absolute path to the cleaned transcript file produced by filter-session-transcript.sh>

## Disposed-id lock list

The following thread ids are disposed and must never be re-raised under any name:
<comma-separated list of disposed thread ids from seed.disposed_threads[*].id>
```

### Requirements

- **Seed**: a file path only. The persona uses Read to load the full JSON. Not inline JSON. Not a summary. The path must point to the temp seed file written by the orchestrator in step 3a.
- **Transcript**: a file path only. The persona uses Grep and Read to locate relevant spans. The path must point to the output of `filter-session-transcript.sh`, not the raw session JSONL.
- **Disposed-id lock list**: the `id` values from all entries in `seed.disposed_threads`. A persona that raises a refutation with a disposed id is producing an invalid result — the orchestrator discards it without judging.

## Judge input (per refutation)

The orchestrator spawns 3 judge instances per refutation. Each receives:

```
## Refutation

<single refutation object as JSON>

## Seed (read-only context)

seed_path: <absolute path to the seed JSON file produced in step 3a>

## Transcript

transcript_path: <absolute path to the cleaned transcript file>
```

### Requirements

- **Refutation**: a single refutation object (normal form), not an array.
- **Seed**: a file path only. Read-only — the judge reads the file and must not propose changes to the seed.
- **Transcript**: same cleaned transcript path used by personas.

## Cleaned transcript path

The cleaned transcript is produced by running:

```bash
bash ~/.dotfiles/claude-code-shared/scripts/filter-session-transcript.sh <output-path>
```

before spawning any persona. The path is reused for all personas and all judge instances in the same verification run. The orchestrator is responsible for:
1. Resolving the session JSONL (via `CLAUDE_CODE_SESSION_ID` + `CLAUDE_CONFIG_DIR`, or `transcript_path` env var)
2. Running the pre-filter script once
3. Passing the output path to every agent in the run
4. Deleting the temp file after the verification stage completes
