# The eight checks

Run all of them. Each section gives what to look for, what each grade means, and why it matters.
The greps are starting points, not a script — read what they return and judge it. They use `rg`; swap in
`grep -rn` where it is not installed.

A check's grade is its worst finding. When two checks disagree about the same fact, the rule is stated
in the check itself — see 4 and 7, which both touch untracked-but-needed files.

---

## 1. Port binding

`wop` picks a free port per service from `port_range` and exposes it as `{<service>_port}`. A service
that ignores it listens on the same port in every worktree, and the second `wop up` fails or silently
attaches to the first branch's server.

**Look for:**

```bash
rg -n 'listen\(|\.listen|bind|Addr:|port\s*[:=]\s*[0-9]{4}' --glob '!node_modules'
rg -n 'localhost:[0-9]{4}|127\.0\.0\.1:[0-9]{4}|0\.0\.0\.0:[0-9]{4}'
rg -n '"-p"|--port[= ][0-9]{4}' package.json Procfile Makefile docker-compose.y*ml 2>/dev/null
```

Check both sides. A backend that honours `PORT` is only half the job: if the frontend hardcodes
`http://localhost:3000` for its API, every worktree's frontend talks to whichever backend happens to
own 3000.

- 🔴 the listen port is a literal, or a client points at a literal port
- 🟡 the port comes from a flag the start command can set, so `cmd` in `.devmanager.yml` can pass it
- 🟢 every port is read from the environment, with or without a default

## 2. Database identity

Each worktree gets its own database, named by `name_pattern`. The app has to learn that name at
runtime. A literal database name means all branches share one database — the worst failure mode here,
because nothing errors.

**Look for:**

```bash
rg -n 'database:|dbname|DB_NAME|DATABASE_URL' config/database.yml config/settings*.py .env* 2>/dev/null
rg -n 'postgres(ql)?://|mysql://|mongodb://|redis://' --glob '!*.lock' --glob '!node_modules'
rg -n 'url\s*=' prisma/schema.prisma 2>/dev/null
```

Usual suspects: `config/database.yml` (Rails), `settings.py` / `DATABASES` (Django),
`prisma/schema.prisma`, `knexfile.js`, `ormconfig.json`, `application.properties`,
`docker-compose.yml` environment blocks.

- 🔴 a database name or connection URL is a literal in committed config
- 🟡 read from the environment but with a literal fallback that works, so a missing variable silently
  lands everyone on the shared database
- 🟢 read from the environment, and failing loudly when unset

## 3. Env files

`wop` writes `.env` into the worktree, built from `env_source` and patched with the `env` map.

**Look for:**

```bash
git ls-files | rg '^\.env|/\.env'          # tracked env files — any hit is a red
cat .gitignore | rg -n 'env'
ls -a .env* 2>/dev/null                    # is there a template to use as env_source?
```

- 🔴 a real `.env` is tracked in git (`wop`'s generated file then collides with a tracked file, and
  the worktree shows up dirty), or secrets are committed
- 🟡 `.env` is ignored but there is no `.env.example` or equivalent, so `env_source` has nothing to
  start from and every variable must be written out in the `env` map
- 🟢 ignored, with a committed template

## 4. Required but ignored files

A worktree is a fresh checkout. Anything git does not track does not appear there. This is the check
people forget, and it fails at the first `wop up`.

**Look for:**

```bash
git status --ignored --short | rg -v 'node_modules|vendor|\.cache|dist|build|tmp|log'
git check-ignore -v $(ls -a) 2>/dev/null
```

Then ask: of these, which does the app need to boot? Typical answers: `config/master.key` or
`config/credentials/*.key`, service-account JSON, local TLS certs, `.npmrc` with a token,
`google-services.json`, SQLite files holding seed data.

**A hook can usually copy such a file from the main checkout**, which is what decides the grade. There
is no `wop` variable for the main checkout's path, but git gives it, and hooks run inside the worktree:

```yaml
after_create:
  - mkdir -p config && cp "$(dirname "$(git rev-parse --git-common-dir)")/config/master.key" config/master.key
```

In a worktree `.git` is a file, so `--git-common-dir` resolves to the **main** checkout's `.git` and its
parent is the main checkout. The `mkdir -p` is not optional: when a directory holds nothing but ignored
files, it does not exist in a fresh worktree at all, and the `cp` fails without it.

- 🔴 the app cannot boot without a file that git does not track, **and** it is not present in the main
  checkout either — so no hook can produce it
- 🟡 the file is in the main checkout and a hook can copy or regenerate it — record the exact command
  for `wop-configure` to put in `after_create`
- 🟢 a fresh checkout plus `after_create` is enough

**Tiebreak with check 7.** The copy hook works for a developer who already has the file. That a *new*
developer must still obtain it by hand is check 7's problem, not this one. So the same file is 🟡 here
and contributes a 🔴 to check 7. Grade it that way in both rather than picking one.

**Re-run this check against every start command somebody gives you.** A command supplied in conversation
rather than found in the repo — `bundle exec sidekiq -C config/sidekiq.yml`, say — is exactly where an
untracked dependency hides. Check that each file it names exists and is tracked before putting the
command anywhere near `.devmanager.yml`. A file that is in neither the repo nor the main checkout is the
🔴 case, not the 🟡 one: no hook can copy what does not exist.

## 5. Worktree hostility

Three things differ in a worktree, and tooling sometimes assumes otherwise.

**`.git` is a file, not a directory.** In a worktree it contains `gitdir: /path/to/.git/worktrees/x`.

```bash
rg -n '\.git/hooks|\.git/HEAD|\.git/config|\.git/refs' --glob '!node_modules'
rg -n 'is_dir|isDirectory|-d ["'"'"']?\.git'
```

**Submodules are not initialised** by `git worktree add`.

```bash
test -f .gitmodules && cat .gitmodules
```

**Absolute paths to the main checkout** break the moment the code runs from a sibling directory.

```bash
rg -n '/Users/|/home/[a-z]|~/[A-Za-z]' --glob '!*.lock' --glob '!node_modules'
```

Markdown is included on purpose: a path in a README is the yellow case below, so excluding docs would
hide the only finding this check grades yellow.

- 🔴 something reads `.git` as a directory, or submodules are required, or an absolute path to the
  main checkout is baked into config or a script
- 🟡 an absolute path appears only in developer docs or a comment
- 🟢 everything resolves relative to the repo root

## 6. Fixed OS-level resources

Ports and databases are not the only things two branches can collide on.

```bash
rg -n '\.sock|\.pid|/tmp/[a-z]|/var/run'
rg -n 'container_name:|volumes:|ports:' docker-compose.y*ml 2>/dev/null
rg -n 'redis|cache\.(get|set)|Redis\.new' --glob '!node_modules' | head -40
```

- **Sockets, pidfiles, tmp directories** at a fixed path: the second branch overwrites the first.
- **Compose** `container_name`, named volumes, and fixed host-port mappings (`"3000:3000"`) are all
  one-per-machine.
- **Redis** does not isolate per branch. `wop` gives you `{db_name_<logical>}` and deletes exactly
  `<that-prefix>:*` on teardown. If the app does not prefix its keys with it, branches share data
  **and** `wop down` cannot clean up. Whether this is fixable turns on how keys are built, and there are
  three cases, not two: one helper every key goes through is mechanical; keys built inline all over the
  codebase is a report item; **a handful of inline call sites is a judgement call** — prefixing them is a
  real fix, but picking the scheme commits everything else that touches Redis, including code this repo
  may not contain. Treat it as a decision to raise, not a substitution to apply.
- Also: fixed S3 buckets, search indices, and queue names, when the app writes to them in
  development.

- 🔴 a fixed path or name that two simultaneous worktrees would both claim
- 🟡 a shared external resource that is read-only or harmless to share
- 🟢 every such name derives from the environment

## 7. Scripted setup

`after_create` hooks run unattended, in the service's `dir`, with no TTY. If nobody has written down
how to get the app running, there is nothing to put there.

**Look for:** `bin/setup`, `Makefile` targets, `scripts/`, the README's setup section, CI workflow
steps — CI is often the only honest record of how the app really boots.

- 🔴 setup needs a human: an interactive prompt, a password typed in, a file fetched from somewhere
  by hand
- 🟡 the steps exist but are only prose in a README, or they are not idempotent, or they take long
  enough to make every `wop up` painful
- 🟢 one unattended command chain installs, migrates and seeds

## 8. Existing `.devmanager.yml`

```bash
if [ -f .devmanager.yml ]; then
	command -v wop >/dev/null && wop config show || echo "wop is not installed"
else
	echo "no .devmanager.yml yet"
fi
```

Neither "no config yet" nor "`wop` not installed on this machine" is a finding about the repo: the first
is 🟢 because `wop-configure` writes it, and the second means this check cannot be run — say so instead
of grading it. Guarding the command matters because a bare `test -f … && wop config show` exits non-zero
when the file is simply absent, which reads as a failure.

- 🔴 present but `wop config show` rejects it, or `port_range`s overlap between services, or `hooks`
  keys name services that do not exist
- 🟡 present and valid but incomplete — a service missing, no databases, no hooks
- 🟢 absent (`wop-configure` will write it) or present and complete
