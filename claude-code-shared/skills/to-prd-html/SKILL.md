---
name: to-prd-html
description: Turn the current conversation context into an interactive HTML PRD and save it to docs/prd/. Use when user wants to create a PRD from the current context with rich interactive output.
---

This skill takes the current conversation context and codebase understanding and produces an interactive HTML PRD. Do NOT interview the user. Synthesize what you already know.

## Process

1. **Explore the repo** to understand the current state of the codebase, if you haven't already. Use the project's domain vocabulary (from `CONTEXT.md` and ADRs in `docs/adr/` if they exist) throughout the PRD. If neither `CONTEXT.md` nor `docs/adr/` exist, explicitly note that no project-specific vocabulary sources were found and proceed with the best domain terms available from the conversation context.

2. **Sketch the major modules** you will need to build or modify. Actively look for opportunities to extract deep modules that can be tested in isolation.

   A deep module encapsulates a lot of functionality in a simple, testable interface that rarely changes.

   Check with the user that these modules match their expectations and which ones they want tests written for.

3. **Ask: work or personal? (MANDATORY).** You MUST ask before proceeding. Do not skip this step. Do not assume or infer the answer. Always prompt the user:

   ```
   Is this PRD for work or personal?
   1. Work
   2. Personal
   ```

   This determines the color theme and branding applied to the HTML output:
   - **Work**: use `theme-work.css` from this skill's directory. Light, professional, blue-anchored palette. Include the company logo SVG at the top of the page (see `logo-work.svg` in this skill's directory).
   - **Personal**: use `theme-personal.css` from this skill's directory. Dark, warm, ochre/earth-tone palette. No logo.

   Read the chosen theme file and replace the `:root` CSS custom properties block in the template with the values from the theme file. Also update the `font-family` declarations on `body` and heading elements to use `var(--font-body)` and `var(--font-heading)` respectively.

   For **work** PRDs, insert the logo SVG (from `logo-work.svg`) right after the opening `<body>` tag, wrapped in a `<div class="logo" style="margin-bottom: 1.5rem;">` container. Set the SVG height to `36px`.

4. **Derive a slug** from the feature name, lowercase, kebab-case, max ~40 chars (e.g. `user-auth-flow`).

5. **Ask where to write (MANDATORY).** You MUST ask before writing anything to disk. Do not skip this step:

   ```
   Where should this PRD go?
   1. Current branch
   2. New spike branch
   3. New feat branch
   4. New fix branch
   ```

   If the user picks **2**, **3**, or **4**:
   - Propose a branch name derived from the slug: `spike/{slug}`, `feat/{slug}`, or `fix/{slug}`.
   - Let the user accept or type a custom name (e.g. a Linear ticket slug).
   - Run `git switch -c {branch-name}`. If the switch fails (dirty working tree), tell the user to commit or stash first and stop.
   - Continue on the new branch.

   If the user picks **1**, continue on the current branch (existing behavior).

6. **Confirm output directory (MANDATORY).** Resolve the absolute path of `docs/prd/` relative to the current working directory. Ask the user before writing:

   ```
   PRD will be saved to: /absolute/path/to/docs/prd/
   Is that correct? If not, provide the path you'd like instead.
   ```

   Use whatever path the user confirms (create it if it doesn't exist). Do not skip this step.

7. **Determine the file prefix** by running the `next-prefix.sh` script in this skill's directory: `~/.dotfiles/claude-code-shared/skills/to-prd-html/next-prefix.sh`. It returns a `YYYYMMDD-HHMM` timestamp prefix.

8. **Write the HTML PRD** to `{confirmed-dir}/{prefix}-{slug}.html`. Never auto-commit. Use the template from `~/.dotfiles/claude-code-shared/skills/to-prd-html/template.html` for the HTML structure.

9. Tell the user the path and suggest running `/to-tasks` next.

## HTML Output Rules

### Template usage

The template file (`template.html`) provides the outer shell: CSS, JavaScript for interactivity, and layout skeleton. You fill in the content sections. Do NOT modify the shell CSS/JS unless the content requires it.

### Embedded JSON for machine consumption

Every HTML PRD MUST contain a `<script type="application/json" id="prd-data">` block at the bottom of `<body>`, before the closing `</body>` tag. This block contains the PRD content as structured JSON so that `/to-tasks` and other agents can extract it without parsing HTML.

JSON structure:

```json
{
  "title": "PRD title",
  "slug": "kebab-case-slug",
  "created": "ISO 8601 timestamp",
  "problem_statement": "The problem in plain text",
  "solution": "The solution in plain text",
  "user_stories": [
    {
      "actor": "developer",
      "feature": "what they want",
      "benefit": "why they want it"
    }
  ],
  "implementation_decisions": [
    "Decision 1 as plain text",
    "Decision 2 as plain text"
  ],
  "testing_decisions": [
    "Testing decision 1",
    "Testing decision 2"
  ],
  "out_of_scope": [
    "Item 1",
    "Item 2"
  ],
  "further_notes": [
    "Note 1",
    "Note 2"
  ]
}
```

### Mandatory interactive features

Every HTML PRD MUST include:

1. **Collapsible sections.** Each major section (Problem, Solution, User Stories, Implementation, Testing, Out of Scope, Notes) is collapsible via `<details>/<summary>`. All expanded by default.

2. **Tabbed views.** The three core content sections (User Stories, Implementation Decisions, Testing Decisions) are presented as tabs. User can switch between them without scrolling.

3. **Color-coded tags.** Use functional color sparingly:
   - Risk/complexity indicators on implementation decisions (red = high risk, amber = medium, green = low)
   - Priority indicators on user stories if priorities differ
   - Module names as colored pills for visual grouping

4. **Jump links / TOC.** Fixed or sticky table of contents at the top with anchor links to every section. Shows review progress.

5. **Review checklist.** Each section has a checkbox. Progress bar at top shows "N/M sections reviewed." Visual only, resets on refresh. Helps the reviewer track what they've actually read.

### Conditional features

Include these ONLY when the PRD content warrants them:

6. **Inline SVG architecture diagram.** Generate when there are 3+ modules with non-trivial relationships. Show modules as boxes, arrows for dependencies/data flow. Keep it simple. No decorative elements.

7. **Side-by-side option comparison.** Generate when the PRD presents alternatives or trade-offs that were considered. Two-column layout with pros/cons.

### Design constraints

- Single self-contained `.html` file. No external dependencies. CSS in `<style>`, JS in `<script>`.
- Dark mode by default. Dark background (#1a1a2e or similar), light text, high contrast.
- Minimal aesthetic. No gradients, no glass morphism, no emoji headers, no decorative elements.
- Serif or clean sans-serif body text. 60-75ch line width. Generous spacing.
- Mobile responsive. Include viewport meta tag.
- Functional color only: risk tags, status indicators, module pills. No decorative color.

### Content rules (same as markdown PRD)

- User stories: minimum 5, extensive coverage, format: As a `<actor>`, I want `<feature>`, so that `<benefit>`
- Implementation decisions: modules, interfaces, architecture, schema changes, API contracts. No file paths or code snippets.
- Testing decisions: what makes a good test, which modules, prior art in codebase.
- Out of scope: explicit exclusions.
