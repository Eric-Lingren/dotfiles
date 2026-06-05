# Standard Metrics Dev Commands

Source of truth: https://standard-metrics-quaestor-web.readthedocs-hosted.com/en/latest/mkdocs/dev_environment/

---

## Backend

**Start backend server** (from `./app`)
```bash
python manage.py runserver_plus --keep-meta-shutdown
```

**shell_plus** (from `./app`)
```bash
python manage.py shell_plus
# or via dev wrapper:
dev dj shell_plus
# on a sandbox:
dev dj -e my-sandbox shell_plus
```

**Add superuser + firm membership** (from `./app`)
```bash
python manage.py createsuperuser
python manage.py shell_plus
# then in shell_plus:
UserFirmMembership.objects.create(firm_id=11, user=User.objects.last())
```

**Make migrations**
```bash
./manage.py makemigrations
# or add an empty migration for a specific app:
python manage.py makemigrations company --empty
```

**Fake a migration**
```bash
python manage.py migrate venture 0399_tearsheetmetricsblock_end_date_and_more --fake
```

**Revert to a previous migration**
```bash
# 1. Migrate DB state back to before the bad migration
python manage.py migrate info_sharing 0042
# 2. Delete the migration file
rm app/info_sharing/migrations/0043_kpirequest_display_order.py
# 3. Fix linear history check
git checkout main -- info_sharing/migrations/max_migration.txt
# 4. Remake the migration
python manage.py makemigrations
# 5. Apply it
python manage.py migrate
```

**Start celery worker** (from `./app`)
```bash
celery -A task.celery worker --loglevel=info -Q user_waiting,notifications,integrations,longtasks,whenever,celery,email_parsing,doc_parsing
```

**Halt / flush queued celery tasks**
```bash
redis-cli flushall
```

**Celery flower** (from `./app`, separate terminal)
```bash
celery -A task.celery flower
# navigate to: http://localhost:5555/
```

**Enable django-silk on a sandbox** (requires helm access)
```bash
helm upgrade quaestor-web helm/quaestor-web --reuse-values --set useSilk=true \
&& helm upgrade quaestor-web helm/quaestor-web --reuse-values --set migrate.enabled=true \
&& kubectl rollout restart deployment/quaestor-web
```

**Docker python shell** (older local setups)
```bash
docker-compose -p quaestor exec django python3 manage.py shell_plus
```

**Reboot postgres**
```bash
brew services restart postgresql@16
brew upgrade postgresql@16
```

**Format with Ruff**
```bash
ruff check --fix . && ruff format .
```

**Run Mailhog**
```bash
brew update && brew install mailhog && mailhog
# navigate to: http://localhost:8025/
```

**Pre-commit hooks** (from `./app`)
```bash
pip install pre-commit
pre-commit install
# commit message template:
git config commit.template .gitmessage
```

---

## Frontend

**Start frontend** (from `./client`)
```bash
yarn dev
```

**Storybook** (from `./client`)
```bash
yarn storybook
```

**TypeScript check**
```bash
npx yarn type-check
# or via dev wrapper:
dev type-check
```

**Lint fix**
```bash
yarn lint --fix
```

**Biome lint**
```bash
yarn biome check --max-diagnostics=50
# lint only one error type:
yarn lint --only=lint/correctness/noUnusedFunctionParameters ./src/
```

**Biome format a file**
```bash
yarn run biome format --write <file-name>
git add <file-name>
git commit -m "chore: format with biome" --no-verify
git push
```

**Update Biome snapshot**
```bash
yarn vitest biome-errors.vitest.test.ts -u
```

**Prettier format a file**
```bash
yarn prettier -w src/pages/path/to/File.tsx
```

**Kill stale Next.js server on port 3000**
```bash
kill -9 $(lsof -ti :3000)
```

**Generate client API schema**
```bash
dev gen-client-api
```

**Update Node version**
```bash
fnm list
fnm list-remote
fnm install <version>
fnm use <version>
fnm default <version>
cd ~/Documents/dev/Quaestor-Web
mamba env update -f dev/environment.yml
node --version
```

---

## Sandbox

All sandbox commands require AWS authentication (`dev aws-refresh-env` first).

**List sandboxes**
```bash
dev sandboxes ls
```

**Create sandbox** (interactive)
```bash
dev sandboxes create
# advanced — custom credentials, per-service resource tuning:
dev sandboxes create --advanced
```

**Update sandbox** (redeploy from latest branch)
```bash
dev sandboxes update
```

**Delete sandbox**
```bash
dev sandboxes delete
```

**Shell into a sandbox container**
```bash
dev sandboxes sh                      # defaults: your OS username + backend service
dev sandboxes sh <optional-sandbox-name> 
dev sandboxes sh <my-sandbox-name> frontend      # explicit name + service
# Available services: backend, frontend, mailhog, redis, fastTasks, slowTasks, beatWorker, aiTasks, emailParsingTasks
```

**Run a command on a sandbox container**
```bash
dev sandboxes exec <my-sandbox-name> backend -- python manage.py migrate
# The -- separator is required before the command.
```

**Open a shell on a sandbox** (via dev sh)
```bash
dev sh -e <my-sandbox-name>
dev sh -e <my-sandbox-name> <cmd string>
```

---

## Database

**Sync demo database locally**
```bash
dev remote-to-local demo
```

**Sync anonymized production data locally**
```bash
dev remote-to-local anonymized
```

**Create a DB snapshot**
```bash
dev db-snapshot create <snapshot-name>
```

**Restore a DB snapshot**
```bash
dev db-snapshot restore <snapshot-name>
# skip migrations on restore:
dev db-snapshot restore <snapshot-name> --no-migrate
# operate on the test database:
dev db-snapshot create <name> --test
dev db-snapshot restore <name> --test
```

**List DB snapshots**
```bash
dev db-snapshot ls
```

**Drop a DB snapshot**
```bash
dev db-snapshot drop <snapshot-name>
```

**Generate CI testing DB snapshot**
```bash
dev generate-ci-testing-db
```

**Clear local DB entirely**
```bash
psql postgres -c "DROP SCHEMA public CASCADE;CREATE SCHEMA public;"
```

---

## AWS / Infra

**Install AWS CLI v2**
```bash
dev aws-cli-install
```

**Configure AWS SSO profiles**
```bash
dev aws-configure-sso
```

**Refresh AWS session credentials into app/.env**
```bash
dev aws-refresh-env
# custom profile:
dev aws-refresh-env --profile YOUR_PROFILE_NAME
```

**Update kubeconfig**
```bash
dev kubeconfig
```

**SSH into a production pod** (kubectl — prod only, not for sandboxes)
```bash
kubectx production-main && kubens app
kubectl get pods
kubectl exec -it <pod-name> -- /bin/sh
```

---

## Testing

**Run one Django test**
```bash
pytest company/tests/test_datum_category_views_view.py
pytest stakeholder/tests/views/test_create_stakeholder_update_block_view.py::StakeholderUpdateMetricsBlockCreateTestCase
# -s to see print statements
pytest -s <path>
```

**Pytest coverage**
```bash
pytest --cov module_name --cov-report term-missing module_name
```

**Run one Jest test**
```bash
DEBUG_PRINT_LIMIT=20000 yarn test src/pages/settings/__tests__/UnifiedAccountSelector.test.tsx
```

**Jest coverage**
```bash
DEBUG_PRINT_LIMIT=20000 yarn test --watch --collectCoverage
```

**Jest debugging helpers**
```js
screen.debug(testEl)                   // print element
console.log(api.GET.mock.calls)        // check if API was called
console.log(api.GET.mock.results)      // check data from API call
```

**Run one Playwright test**
```bash
npx playwright test tests/portfolio/logo-screenshot.spec.ts
playwright --debug AddStakeholderButton.spec.ts
PWDEBUG=1 npx playwright test <spec>
# --trace on adds trace video
```

**Playwright interactive codegen**
```bash
npx playwright codegen http://localhost:8080/company/caesar-1bbdd1b4/metrics/
```

**Replay flaky Playwright test from CI**
```
# Download the trace zip from CI, then drag-and-drop at:
https://trace.playwright.dev/
```

---

## Git

**Connect a Linear task to an existing git branch**
```bash
git checkout <existing-branch-name>
# In Linear: open the issue → "Copy Git branch name to clipboard"
git branch -m <linear-git-branch-name>
git push origin -u <linear-git-branch-name>
```

**Make a smaller branch from a larger one**
```bash
git checkout <local-feature-branch>
git diff <main-commit-number> --stat          # see what changed vs main
git checkout -b <smaller-feature-branch-name>
git reset <main-commit-number>               # unstage all commits
git status                                   # confirm all files visible
git add <file-name>                          # re-stage only what you want
git diff --cached --stat                     # confirm staged diff
git checkout -- .                            # discard everything else
git status                                   # confirm clean
git commit -m "..."
git push
```

**Resync a local file with main** (pull main's copy over local)
```bash
git checkout main path/to/file
```

**Fix merge conflicts in generated files**
```bash
git checkout <branch-name>
git fetch origin main
git pull --rebase origin main
# For each conflicting generated file — take theirs:
git checkout --theirs <relative-file-path>
git add <relative-file-path>
git rebase --continue
# Regenerate the file, commit, push:
git push origin <branch-name> --force
```

**Check running processes on port 8000**
```bash
lsof -i TCP:8000
kill -9 <pid>
```

---

## Dev Tooling

**Start local dev environment** (nginx, Django, Next.js)
```bash
dev start
```

**Initial setup** (binaries, services, project dependencies)
```bash
dev setup
```

**Install pip / npm dependencies**
```bash
dev install
```

**Lint**
```bash
dev lint
dev lint --fix
```

**Type check (Python)**
```bash
dev type-check
```

**Lock backend requirements**
```bash
dev lock
```

**Jupyter notebook**
```bash
dev jupyter
```

**Host documentation**
```bash
dev docs
dev docs --live   # auto-refresh on changes
```

**Activate conda venv manually**
```bash
conda activate /Users/ericlingren/mambaforge/envs/sm
```

---

## AI Doc Parsing (AIDP)

**Boot LocalStack + deploy CDK stack**
```bash
dev aidp up
```

**Stop LocalStack** (preserve state)
```bash
dev aidp down
```

**Tear down + wipe state + re-bootstrap**
```bash
dev aidp reset
```

**Tail LocalStack logs**
```bash
dev aidp logs
```

---

## gx Git Toolkit

Personal git toolkit for dotfiles and personal repos. All verbs live in `~/.dotfiles/.scripts/`. From skills, always invoke via absolute path (aliases are absent in non-interactive shells).

**gxcheck** — read-only branch state reporter. Outputs MERGED, FOREIGN, STALE, REMOTE_GONE, and ON_BASE signals. Always exits 0 (advisory only).
```bash
~/.dotfiles/.scripts/gxcheck
```

**gxpush** — preview-and-confirm push. Shows staged, will-add, excluded, and secret files before any git operation. Default confirmation is N.
```bash
~/.dotfiles/.scripts/gxpush           # stage tracked files, commit, push
~/.dotfiles/.scripts/gxpush --all     # stage everything (git add -A), confirm, push
~/.dotfiles/.scripts/gxpush --pick    # interactive hunk selection (git add -p)
~/.dotfiles/.scripts/gxpush --pr      # push and open PR (uses pr-desc --stdout)
~/.dotfiles/.scripts/gxpush --push-only  # skip staging/commit; push only (for cherry-pick flows)
```

**gxmove** — relocate uncommitted changes to another branch.
```bash
~/.dotfiles/.scripts/gxmove <target-branch>
```

**gxclean** — list and delete merged local branches. Shows prototype/* branches as [PRIORITY]. Default confirmation is N.
```bash
~/.dotfiles/.scripts/gxclean
```

**gxsync** — fetch + merge origin/<base_branch> into current branch. No rebase, no force-push.
```bash
~/.dotfiles/.scripts/gxsync
```
