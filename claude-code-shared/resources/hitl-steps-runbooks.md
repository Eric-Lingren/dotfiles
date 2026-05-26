# HITL Steps Runbooks

Reusable step-by-step runbooks for manual follow-ups. Referenced by to-tasks, run-tasks, and run-task-followups. Use `{placeholder}` for project-specific values.

<!-- Runbooks are added/updated automatically when friction is detected during /run-task-followups -->

## Quality bar

Every step must be concrete enough that the user can execute it without asking "how?"

Bad: "Insert credit rows in user_credits"
Good: "Run this SQL in Supabase dashboard (SQL Editor > New Query):
```sql
INSERT INTO user_credits (user_id, credit_type, amount, created_at)
VALUES ('{user_id}', 'onboarding', 100, now());
```
Verify: `SELECT * FROM user_credits WHERE user_id = '{user_id}';`"

If a step says "update X" or "add Y", it must include the exact command, exact SQL, exact config key, or exact dashboard click path.

---

## Apply Supabase database migrations

Steps:
1. Verify CLI is linked to the correct project:
   `supabase link --project-ref {project-ref}`
   Get the ref from: Supabase dashboard > project > Settings > General > Reference ID.
2. Run: `supabase db push`
3. Verify migrations applied: `supabase migration list`
4. Lint new migration files: `supabase db lint --linked`

Notes:
- `db push` and `migration list` connect to the linked remote project automatically.
- `db lint` requires the `--linked` flag (it defaults to local DB, which may not be running).
- If `db push` fails with `permission denied to alter role` or `SUPABASE_DB_PASSWORD` error, skip the CLI and apply the SQL directly in the Supabase dashboard SQL Editor instead (see fallback below). This is a known CLI bug with certain project configurations.

Fallback (when `supabase db push` fails with permission error):
1. Open Supabase dashboard > your project > SQL Editor > New Query.
2. Paste the contents of the migration file and run it.
3. Verify with: `SELECT column_name FROM information_schema.columns WHERE table_name = '{table_name}';`

Enrichment:
- List migration files: `ls supabase/migrations/` and include the specific filenames being applied.
- If migration creates tables or columns, show the schema changes so the user can verify.
- Find project ref: check `supabase/.temp/project-ref` or ask user to get it from Supabase dashboard.

## Deploy Supabase edge function

Steps:
1. Run: `supabase functions deploy {function-name}`
2. Verify: `supabase functions list` (confirm {function-name} shows updated timestamp)
3. Smoke-test the affected flow in the UI or with a curl call to confirm the fix is live.

Notes:
- Any task that modifies files under `supabase/functions/{name}/` requires a deploy of that function before the fix is live in production.
- New helper files added alongside `index.ts` (e.g. `activateMembership.ts`) are bundled automatically by the deploy command. No extra steps needed.

Enrichment:
- Find function name: `ls supabase/functions/` and match against the trigger task's diff (look for changed files under `supabase/functions/{name}/`).
- Check for env vars the function uses: grep `Deno.env.get` in the function source. List each var and whether it's set in Supabase dashboard.
- Always include a smoke-test step describing the specific user flow the task fixes.

## Add env var to {platform}

Steps:
1. Go to {platform} dashboard > {app-name} > Settings > Environment Variables
2. Add variable: Name: `{VAR_NAME}`, Value: {value_source}
3. Redeploy or restart the service if required by the platform

Enrichment:
- Find var names: grep `.env*` files, `process.env.`, `Deno.env.get()`, `import.meta.env` in the diff and codebase.
- Find value sources: check `.env.example`, README, or provider docs. Name the specific provider dashboard and page.
- Find platform: check deployment config (wrangler.toml, supabase/config.toml, vercel.json, netlify.toml).

## Configure Cloudflare Email Routing to Worker

Steps:
1. Deploy the Worker first (routing UI only shows deployed Workers as targets):
   ```
   cd cloudflare/{worker-dir}
   wrangler deploy
   ```
2. Verify Worker appears in Cloudflare dashboard > Workers & Pages. Confirm `{worker-name}` is listed.
3. Go to Cloudflare dashboard > {domain} > Email > Email Routing > Routing Rules.
4. Click "Create address" or "Add custom address".
5. Set "To address": `{email-address}` (e.g. read@ericlingren.com).
6. Set "Action": Send to a Worker.
7. Select Worker: `{worker-name}`.
8. Click Save.
9. Verify DNS tab shows MX records added for Cloudflare Email Routing.
10. Verify Email Routing status shows "Enabled".

Notes:
- "Send to a Worker" action does NOT appear if the Worker has not been deployed yet. Deploy first.
- Requires Cloudflare Email Routing to be enabled for the domain (free feature).

Enrichment:
- Find worker name: read `cloudflare/{worker-dir}/wrangler.toml`, `name` field.
- Find email address: grep wrangler.toml for destination address comment or check task description.
- Find domain: check Cloudflare dashboard or grep `workers_dev = false` in wrangler.toml configs.

## Run database query (manual)

Steps:
1. Open {platform} dashboard > SQL Editor > New Query
2. Run:
```sql
{query}
```
3. Verify: `{verification_query}`

Enrichment:
- Find table/column names: read the relevant migration files or grep the schema.
- Build the exact SQL from the task context. Include column names, values, WHERE clauses.
- Build a SELECT verification query the user can run to confirm.
