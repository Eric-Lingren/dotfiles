---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
model: opus
effort: xhigh
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.

For each question:
1. Ask exactly ONE question per turn. One question mark. No sub-questions, no compound "X and Y?" questions, no follow-ups in the same message.
2. Provide your recommended answer for the question you ask. State what you think the answer should be and why.
3. When asking your first question, briefly signal the other major branches of the decision tree you plan to explore later, so the user knows you see the full picture.

Before formulating your question, explore the codebase first. If a question can be answered by reading code or project files, explore the codebase instead of asking the user.

## Session end protocol

When all major branches are resolved, signal the end explicitly:

> "Grill session complete. All branches resolved."

Then ask the user ONE question using `AskUserQuestion`:

> "What would you like to do with this?"

Options:
- **Run prototype** - explore ideas, hypotheses, and UI/logic options before committing to a PRD (runs `/prototype`)
- **Create a PRD** - write a PRD doc to `docs/prd/` to share with your team (runs `/to-prd-html`)
- **Create a task file** - write a tasks JSON for `/run-tasks` to start building
- **Nothing yet** - session was just for thinking it through

**CRITICAL RULES:**
- Do NOT implement any code, create any files, or make any changes after the grill session ends without explicit user authorization from this question.
- Answering "yes" or "yep" to a specific scoped question during the session ("do I have permission to delete X?") does NOT authorize broader implementation. Specific questions have specific scope.
- Wait for the user's answer before doing anything.