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
1. Run: `supabase db push`
2. Verify migrations applied: `supabase migration list`
3. Lint new migration files: `supabase db lint --linked`

Notes:
- `db push` and `migration list` connect to the linked remote project automatically.
- `db lint` requires the `--linked` flag (it defaults to local DB, which may not be running).

Enrichment:
- List migration files: `ls supabase/migrations/` and include the specific filenames being applied.
- If migration creates tables or columns, show the schema changes so the user can verify.

## Deploy Supabase edge function

Steps:
1. Run: `supabase functions deploy {function-name}`
2. Verify: `supabase functions list` (confirm {function-name} appears)

Enrichment:
- Find function name: `ls supabase/functions/` and match against the trigger task's diff.
- Check for env vars the function uses: grep `Deno.env.get` in the function source. List each var and whether it's set in Supabase dashboard.

## Add env var to {platform}

Steps:
1. Go to {platform} dashboard > {app-name} > Settings > Environment Variables
2. Add variable: Name: `{VAR_NAME}`, Value: {value_source}
3. Redeploy or restart the service if required by the platform

Enrichment:
- Find var names: grep `.env*` files, `process.env.`, `Deno.env.get()`, `import.meta.env` in the diff and codebase.
- Find value sources: check `.env.example`, README, or provider docs. Name the specific provider dashboard and page.
- Find platform: check deployment config (wrangler.toml, supabase/config.toml, vercel.json, netlify.toml).

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
