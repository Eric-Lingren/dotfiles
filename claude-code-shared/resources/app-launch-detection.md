---
name: app-launch-detection
description: Ordered discovery rules for launch context (start_command, base_url, storageState, Playwright module) used by run-tasks and debug before spawning the browser-checker agent.
---

# App Launch Detection

All skills that spawn the browser-checker agent reference this document. Do not inline these discovery rules in skill files.

## Purpose

Before spawning the browser-checker agent, the calling skill (run-tasks, debug) must resolve four pieces of launch context:

1. `start_command` — how to start the dev server
2. `base_url` — where the app listens
3. `storageState` path — pre-authenticated browser state, or none
4. Playwright module location — project-local, global, or unavailable

Resolve each in the order listed below. Stop at the first successful match.

---

## 1. start_command

Ordered discovery:

1. **Project `CLAUDE.md`** — look for a line like `Dev server: <command>` or a `## Dev` / `## Running` section.
2. **`package.json` scripts** — check in this order: `dev`, then `start`. Use the first one found.
3. **Framework defaults** — if `package.json` exists but neither key is present, infer from dependencies:
   - `vite` in deps → `npm run dev` (Vite default)
   - `next` in deps → `npm run dev` (Next.js default)
   - `react-scripts` in deps → `npm start` (CRA default)
   - `express` or bare Node → look for `index.js` or `server.js`; use `node <file>`
4. **No start command found** → report the gap to the user and do not start a server. Run the browser check against a server the user started manually if one is already up.

---

## 2. base_url / port

Ordered discovery:

1. **Project `CLAUDE.md`** — look for a line like `Base URL: http://localhost:3000` or `Port: 3000`.
2. **`vite.config.*`** — read `server.port` (default 5173 if present but unset).
3. **`next.config.*`** — read custom `port` option if set (default 3000).
4. **`.env` / `.env.local`** — look for `PORT=<n>` or `NEXT_PUBLIC_BASE_URL=<url>`.
5. **Framework defaults**:
   - Vite: `http://localhost:5173`
   - Next.js / CRA / Express: `http://localhost:3000`
6. **No base_url found** → default to `http://localhost:3000` and note the assumption in the report.

---

## 3. storageState path

Ordered discovery:

1. **`playwright.config.*`** — read `use.storageState` from the project Playwright config.
2. **Known auth-state files** — check these paths in order:
   - `playwright/.auth/user.json`
   - `.auth/storage-state.json`
   - `e2e/.auth/user.json`
3. **Not found** → run unauthenticated. Report in the check result: `"Auth: unauthenticated (no storageState found)"`. Do not block.

---

## 4. Playwright module resolution

Ordered discovery:

1. **Project `node_modules`** — check whether `./node_modules/playwright` or `./node_modules/playwright-core` exists. If yes, use `node check.mjs` normally (Node resolves from project root).
2. **Global install** — run `npm root -g` to get the global modules path. Check whether `$(npm root -g)/playwright` exists. If yes, invoke check.mjs with `NODE_PATH=$(npm root -g) node check.mjs`.
3. **Not found** → return `status: "skipped"` with `skipped_reason: "Playwright module not found in project node_modules or global install"`. Do not install packages, do not block the task. Report and move on.

---

## Caller responsibilities

- **Health-check before starting**: before running `start_command`, poll `base_url` (e.g. `curl -s -o /dev/null -w "%{http_code}" <base_url>`) to see if a server is already up. Start only if nothing responds.
- **Teardown only what you started**: if the caller started the dev server, kill it after the check. If a server was already running, leave it alone.
- **Port-ready polling**: after starting the server, poll `base_url` until it responds (or a timeout, suggested 60 s). Do not spawn the browser-checker until the server is up.
