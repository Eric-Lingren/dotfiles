# Skill Architecture Contracts Overview

Three shared formats, each with a JSON Schema in this directory.

## Format waists

```
SEED (seed-schema.json v2)          TASK (task-schema.json v1)         RUNNER-RESULT (runner-result-schema.json v1)
```

## Full skill interaction map

```
  [conversation / grill session]
          |
          v
       to-seed ─────────────────────────────────────┐
                                                     |
       prototype ─── (option 1: save as seed) ───────┤
                                                     |
                                              seed.json
                                            (docs/seeds/)
                                              /       \
                                             v         v
                                        to-tasks   to-prd-html
                                             ^         |
                                             |         | (embeds seed JSON)
                                             |         v
                                             └── HTML PRD (docs/prd/)
                                                 (to-tasks reads via
                                                  extract-prd-json.sh)

  debug ──────────────────────────────────────┐
  improve-component ──────────────────────────┤
  to-e2e-tasks ───────────────────────────────┤──► task.json ──► run-tasks ──► [TDD loop]
  to-tasks ───────────────────────────────────┤   (docs/tasks/)    |               |
  code-review ─── (HITL vetting first) ───────┘                    |          lint-runner
                                                                    |          test-runner
                                                                    |          e2e-runner
                                                                    |               |
                                                                    |    runner-result verdict
                                                                    |    (inline JSON, schema v1)
                                                                    |
                                                             run-task-followups
                                                             tasks-to-linear
```

## Format details

| Format | Schema | Version | Naming script |
|---|---|---|---|
| Seed | `seed-schema.json` | `"2"` | `scripts/doc-filename.sh <slug> json` |
| Task | `task-schema.json` | `"1"` | `scripts/task-filename.sh <slug>` |
| Runner result | `runner-result-schema.json` | `"1"` | n/a (inline agent response) |

## Validation

Every format-touching skill has a `## Contract` section with a Step-0 bash invocation:

```bash
bash ~/.dotfiles/claude-code-shared/scripts/validate-schema.sh \
  ~/.dotfiles/claude-code-shared/contracts/<format>-schema.json \
  <file-path>
```

Exit 0 = valid. Non-zero = STOP, report stderr, do not proceed.

## Contract files

- [task-contract.md](task-contract.md) + [task-schema.json](task-schema.json)
- [seed-contract.md](seed-contract.md) + [seed-schema.json](seed-schema.json)
- [runner-result-contract.md](runner-result-contract.md) + [runner-result-schema.json](runner-result-schema.json)

## Interactive diagram

[overview.html](overview.html) — full pipeline flowchart with subgraph layers, schema contracts, and skill nodes.
