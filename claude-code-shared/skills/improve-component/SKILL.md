---
name: improve-component
description: Analyze React components or TypeScript/HTML files for reusability, modularity, and hygiene improvements. Separates business logic from presentation, enforces design system usage, and proposes focused refactors. Use when user wants to improve a specific component, clean up a file, or make code more modular.
---

# Improve Component

Analyze specific files or components for modularity, reusability, and hygiene. Propose focused refactors that make components easier to test, reuse, and maintain.

This skill operates on individual files or small clusters of related files.

## Principles

Apply these in order of impact. Not every principle applies to every file. Flag only what matters.

### 1. Business Logic Separation

Business logic and presentation must live in separate layers. A component that fetches data, transforms it, manages state, AND renders UI is doing too much.

**Pattern:** Extract business logic into custom hooks or plain functions. The component becomes a thin rendering layer that receives data and callbacks.

**Test:** Can you test the business logic without rendering anything? Can you test the presentation with stub data and no real API calls? If no to either, the layers are coupled.

**Signals of violation:**
- `useEffect` with fetch/mutation logic inside a component that also renders UI
- State transformations (filtering, sorting, aggregation) mixed with JSX
- Event handlers that contain business rules, not just delegation
- Components that import API clients or service modules directly

### 2. Design System Adherence

Presentation layers should use design system components and tokens wherever possible. Every one-off styled element is a drift risk.

**Before creating any UI element, check:**
- Does a design system component already handle this? (`/src/design-system`, shadcn, or whatever the project uses)
- Does a shared UI component already exist? (`/src/shared-ui` or equivalent)
- Are spacing values using theme tokens, not raw px/rem?
- Are colors, typography, and shadows using theme values?

**Signals of violation:**
- Inline styles with hardcoded values
- Styled-components or CSS that duplicate design system primitives
- Custom button/input/modal/card when a DS version exists
- Raw HTML elements (`<div>`, `<span>`) used for layout instead of DS layout primitives
- Magic numbers for spacing, font sizes, or breakpoints

### 3. Single Responsibility

Each component does one thing. If describing it requires "and", it should split.

**Test:** Describe the component in one sentence. If you need a conjunction, identify the two responsibilities and evaluate whether splitting improves clarity.

**Signals of violation:**
- Component name includes "And" or describes two behaviors
- Multiple unrelated `useEffect` hooks
- Render function has distinct visual sections with independent data needs

### 4. Props Interface Minimality

Fewer props = more reusable. Pass only what the component needs.

**Signals of violation:**
- Receiving a large object but only using 2-3 fields
- Boolean props that toggle between two entirely different render paths (should be two components)
- More than ~6 props (consider grouping or splitting)
- Props passed only to forward to a child (prop drilling)

### 5. Composition Over Configuration

Components with many boolean/enum props that toggle behavior should split into composable pieces.

**Prefer:** `<Card><CardHeader /><CardBody /></Card>`
**Over:** `<Card showHeader showFooter variant="sidebar" />`

**Signals of violation:**
- Multiple boolean props that control which sections render
- `variant` or `type` prop with a switch statement in the render
- Conditional rendering blocks that are each 20+ lines

### 6. Custom Hook Extraction

When a component has complex state logic or effects, extract to a named hook.

**Benefits:** Hook is independently testable. Component becomes declarative. Logic is reusable across components.

**When to extract:**
- 3+ `useState` calls that interact with each other
- `useEffect` + `useState` patterns (loading/error/data)
- State machine logic (multi-step forms, wizards)
- Debounce/throttle/polling patterns

**When NOT to extract:** Single `useState` for UI toggle. Simple form with 2 fields. Extraction adds a file but no clarity.

### 7. Naming Clarity

Names describe what, not how. Names describe what the thing IS, not where it's used.

**Components:** Describe what they render. `InvoiceLineItem` not `TableRow3`. `UserAvatar` not `SmallImage`.
**Hooks:** Describe what state they manage. `useInvoiceForm` not `useFormStuff`.
**Variables:** `isLoading` not `flag`. `selectedUserId` not `id`. `handleSubmit` not `doIt`.
**Files:** Match the primary export. `InvoiceLineItem.tsx` not `row.tsx`.

### 8. Colocation

Things used by one component live next to it. Things shared across components live at the nearest common ancestor.

**Signals of violation:**
- Types defined in a central `types/` folder but used by one component
- Helper functions in `utils/` used by one file
- Constants in a global file but relevant to one feature

### 9. Test Coverage Existence

Check whether a colocated test file exists for the target component.

**Check for:** `ComponentName.test.tsx`, `ComponentName.spec.tsx`, or a `__tests__/` directory containing a matching test file.

**If no test file exists:** Flag it. A component without tests is a refactoring hazard. Note the gap and recommend `/tdd` to backfill.

**If a test file exists:** Glance at it. Flag if it only tests trivial rendering ("renders without crashing") and lacks coverage of meaningful behavior, props, or edge cases.

**This principle does not write tests.** It surfaces the gap. `/tdd` handles the fix.

### 10. File Size as a Signal

Not a hard limit, but files over ~200 lines usually contain extractable pieces. The question is always: does splitting improve clarity, or just scatter code?

**Split when:** Distinct responsibilities exist within the file. Independent testability would improve. A section is reusable elsewhere.
**Don't split when:** The pieces only make sense together. Splitting just creates a file-hopping burden. The file is long but linear and readable.

## Process

### 1. Receive target

User provides one or more file paths. If no paths given, ask: "Which files or components should I look at?"

If the user points at a directory, list the files in it and ask which to focus on. Don't analyze an entire directory unprompted.

### 2. Read and understand

Read the target file(s) fully. Also read:
- Direct imports (one level deep) to understand dependencies
- The test file if one exists
- CONTEXT.md if present (for domain vocabulary)
- The project's design system directory (scan for available components)

Understand what the component does before evaluating how it's structured.

### 3. Identify the design system

Locate the project's design system. Check these locations in order:
1. `/src/design-system/` or `/src/ds/`
2. shadcn component directory (often `/src/components/ui/`)
3. A component library in `package.json` (e.g. `@radix-ui`, `@chakra-ui`, `@mui`)
4. `/src/shared-ui/` or `/src/common/`

If found, scan available components so you can recommend specific replacements. If not found, skip design system checks and note that no DS was detected.

### 4. Analyze against principles

Evaluate each principle. For each violation found, note:
- Which principle is violated
- The specific code location (file:line)
- Why it matters (impact on testability, reusability, or maintainability)
- What the fix looks like (concrete, not vague)

Skip principles that don't apply. Don't manufacture findings.

### 5. Present findings

Group findings by severity:

**Structural** (affects testability or reusability):
- Business logic mixed with presentation
- Missing design system usage where DS components exist
- Components doing multiple unrelated things

**Hygiene** (affects readability and maintainability):
- Naming issues
- Colocation violations
- File size concerns
- Prop interface issues
- Missing or trivial test coverage

Format each finding as:

```
<file>:L<line> — <principle>: <problem>. <fix>.
```

End with a prioritized recommendation: "Start with X because it unlocks Y."

### 6. Clean bill of health path

**MANDATORY.** When analysis finds no structural or hygiene violations worth flagging, you MUST still check for test coverage before ending. This step is not optional.

After presenting the clean summary table:

1. Look for a colocated test file (`ComponentName.test.tsx`, `ComponentName.spec.tsx`, or `__tests__/ComponentName.*`).
2. If no test file exists or the test file only has trivial "renders without crashing" coverage:
   - You MUST use the `AskUserQuestion` tool to prompt the user with a Yes/No question: "Component looks good. No test coverage found. Want me to run `/tdd` to backfill tests?"
   - If user picks Yes: invoke the `/tdd` skill with the target file path.
   - If user picks No: end.
3. If adequate test coverage already exists: note it in the summary and end.

**Do NOT skip this step. Do NOT just mention `/tdd` in text. You MUST use `AskUserQuestion` to prompt.**

### 7. Discuss and refine

Don't start refactoring immediately. Ask the user which findings they want to act on. Some may be intentional trade-offs.

### 8. Execute via TDD

Every approved change goes through `/tdd`. Invoke it with the approved findings and the target file path. TDD handles characterization tests, refactoring, and new behavior on its own.

Seed `/tdd` with:

```
**Target:** {file path}
**Approved changes:**
{numbered list of approved findings with specific fixes from step 6}
```

TDD will check for existing test coverage, write characterization tests if needed, then refactor while keeping tests green. Let it drive the process.

Do not make changes the user didn't approve. Do not bundle "bonus" cleanups.
