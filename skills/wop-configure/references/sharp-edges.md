# Sharp edges

Each of these has bitten someone. Read before writing `.devmanager.yml`, keyed by the symptom it
produces so you can also use this list backwards, from a failure to its cause.

---

## `port_range`s must not overlap

**Symptom:** `wop config show` refuses the config.

Ranges are inclusive and validated across all services. Leave real room — a range of `[3000, 3001]`
supports two branches. `[3000, 3099]` supports a hundred. Space them so growing one never runs into
the next.

## `{branch_slug}` is sanitised two different ways

**Symptom:** the database name in `wop config show` is not what the `.env` contains, and a lookup by
the env value finds nothing.

In env values: `/` → `-`, case preserved. In a database `name_pattern`: lowercased, `/` and `-` both
→ `_`, plus a hash appended whenever slugifying changed anything.

Never build a database name yourself out of the env `{branch_slug}`. Pass `{db_name_<logical>}`, which
is the name `wop` actually created.

## `env_source` resolves from where you run `wop`

**Symptom:** `wop up` reports the template missing, even though the file is plainly in the repo.

The path is relative to the directory `wop` runs in — the main project root — not to the worktree.
`.env.example` means `<project-root>/.env.example`. This is what you want: the template is committed
in the main checkout and read from there for every worktree.

## `migrate_on_up` runs nothing

**Symptom:** `wop up` finishes, the database exists and is empty, and the app dies on a missing table.

The field is parsed and displayed by `wop config show`, and that is all it does today. Migrations go in
an `after_create` hook. Setting it to `true` and stopping there is the single most common reason a
first `wop up` looks successful and the app still will not boot.

## Redis does not isolate per branch

**Symptom:** two branches see each other's cached data, sessions bleed across worktrees, and `wop down`
leaves keys behind.

`{database_url_cache}` is the shared server address, with no namespace in it. The application must
prefix every key with `{db_name_<logical>}`. `wop down` deletes exactly that prefix's keys — nothing
else. If the app cannot be made to prefix, say so rather than writing a Redis entry that only looks
like isolation.

## Never put a password in `connection`

**Symptom:** a database password in git history, in a file everyone on the team pulls.

`.devmanager.yml` is committed. Use `password_env` with the **name** of an environment variable. `wop`
reads it at runtime and errors naming the variable when it is unset.

## `connection` on `sqlite` is a validation error

**Symptom:** `wop config show` rejects the config with a message about sqlite having no server.

sqlite is a file under the worktree. There is nothing to connect to.

## `hooks` keys must be service names

**Symptom:** `wop config show` rejects the config and lists the defined services.

Hooks are grouped by service, not by lifecycle first. A hook under a typo'd or invented name is a hard
error, deliberately — a silently ignored setup step is worse.

## Hooks run with no TTY

**Symptom:** `wop up` hangs forever, or the hook fails with nothing useful on screen.

Hooks are unattended. Anything that prompts — a password, a `y/n`, an interactive generator — blocks
the whole `wop up`. Reach for `--yes`, `--no-input`, `CI=true`, and for npm `--no-audit --no-fund`.

`npm ci` is the reproducible install, but it **hard-errors without a `package-lock.json`** — check the
lockfile is committed before putting it in a hook, or the hook fails on the first run. With no lockfile,
`npm install --no-audit --no-fund` is the one that works.

Hook output lands in `<dir>/<service>.log`; read it there.

## `cmd` has to accept the port it is given

**Symptom:** `wop up` succeeds on the first branch and the second branch's service dies, or silently
serves the first branch's app.

`wop` allocates a port and exposes `{<service>_port}`; it cannot force the process to use it. Either
the app reads `PORT` from the generated `.env`, or `cmd` passes it explicitly
(`npm run dev -- --port $PORT`). `$PORT` works inside `cmd` because it runs through `sh -c` with the
env files loaded. Confirm which of the two applies — do not assume the framework honours `PORT`.

## `copy_from` is literal

**Symptom:** `wop up` errors that a database named `{app}_development` does not exist.

No placeholder expansion happens in `copy_from`. Write the exact existing database name. An existing
target is skipped, a missing source is an error.

## `wop up` cannot take a branch another worktree already holds

**Symptom:** `wop up <branch>` fails because git refuses the same branch in two worktrees.

That is git, not `wop`. Run `wop up --here` from inside the existing worktree: it does everything
except create the worktree, takes the branch from `HEAD`, and records that it must never remove that
directory.
