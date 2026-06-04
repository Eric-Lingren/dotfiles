# Soft Dimension List

> **DRAFT — DATA-GATED**
> The dimensions below are a starter set sketched from early sessions. They have NOT been validated against real grill transcripts or run-tasks outcomes. Do NOT tune this list without measurement data. Changing the content arbitrarily will degrade grill quality in unmeasured ways.

---

These dimensions are **soft guidance only** — non-prescriptive, non-binding. They exist to remind the griller of commonly-missed decision branches, not to mandate coverage. Skip any dimension that is irrelevant to the session topic. Drilling every dimension on every question is the wrong behavior.

## Starter Dimensions

**Data model**
What are the core entities and their relationships? What does each field mean and who owns it?

**State transitions**
What are the valid states for key entities? What triggers transitions? Who can trigger them? Are any transitions irreversible?

**Failure modes**
What fails under load, partial failure, or network partition? What is the recovery path? Is failure silent or visible?

**Boundaries and contracts**
Where are the seams between components or teams? What does each side own? What is the versioning and compatibility story?

**Dependencies and ordering**
What must happen before what? What are the hard ordering constraints vs. soft preferences? What breaks if the order changes?

**Human touch points**
Where does a human need to act, approve, or be notified? What is the latency tolerance for each touch point?

**Scope and out-of-scope**
What is explicitly excluded? What similar-sounding things are NOT being built here? What are the negative guards?

**Reversibility and migration**
Can this be undone? What is the rollback plan? Are there data migration risks? Is there a dual-read or dual-write window?

---

> This list is a starting point for instrumentation. Once session data is available, update the list based on which dimensions produce the most upheld refutations and which are consistently skipped without loss. Do not add or remove dimensions without data.
