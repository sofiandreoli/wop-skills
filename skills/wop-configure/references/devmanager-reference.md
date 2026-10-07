# `.devmanager.yml` reference

Lives at the project root, beside the main `.git`. Every `wop` command runs from that root — the one
exception is `wop up --here`, run from inside an existing worktree.

## Full example

```yaml
app:
  name: my-app

services:
  # Shared env, written to <worktree>/.env and loaded by every service.
  env_source: .env.example
  env:
    DATABASE_URL: "{database_url_primary}"
    DB_NAME_TEST: "{db_name_test}"

  backend:
    dir: api
    cmd: bundle exec rails s -p $PORT
    port_range: [3000, 3099]
    env:
      PORT: "{backend_port}"

  frontend:
    dir: web
    cmd: npm run dev
    port_range: [5173, 5273]
    env:
      PORT: "{frontend_port}"
      VITE_API_URL: "http://localhost:{backend_port}/api"

databases:
  primary:
    adapter: postgresql
    name_pattern: "{app}_{branch_slug}"
  test:
    adapter: postgresql
    name_pattern: "{app}_{branch_slug}_test"

hooks:
  backend:
    after_create:
      - bundle install
      - bin/rails db:migrate
      - bin/rails db:test:prepare
  frontend:
    after_create:
      - npm ci
```

## `app`

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | the worktree directory name and the `{app}` / `{app_name}` tokens |

## `services`

At least one named service. Keys are the service names you use everywhere else (`wop stop <branch>
<service>`, `hooks`, `{<name>_port}`).

| Field | Required | Meaning |
|---|---|---|
| `dir` | no | subdirectory inside the worktree where `cmd` runs; `.` or omitted means the worktree root |
| `cmd` | **yes** | start command, run through `sh -c`, so `$VARS`, `&&` and pipes work. Logs go to `<dir>/<service>.log` |
| `port_range` | **yes** | `[low, high]` inclusive; `wop` takes the first free port. **Must not overlap another service** |
| `env_source` | no | template env file, resolved relative to where you run `wop` |
| `env` | no | key/value pairs patched on top of `env_source` |

### Where env files land

Two places to **write**, and you can use either or both:

- **`env_source` / `env` directly under `services`** → written to `<worktree>/.env`.
- **`env_source` / `env` under a service name** → written to `<worktree>/<dir>/.env` for that service
  (the worktree root when `dir` is omitted or `.`).

### The two files stack at runtime

This is the fact the whole split depends on. When a service starts, `wop` loads **both**
`<worktree>/.env` and `<worktree>/<dir>/.env`, in that order, and the service-specific file wins on any
key they share. On top of that sits the real process environment.

So the shared file is the right home for what every service needs — `DATABASE_URL`, `NODE_ENV` — and the
per-service file for what differs, like `PORT`. A service with `dir: api` sees both; you do not have to
repeat the shared keys under each service.

**Hooks get the same two files**, loaded the same way, plus `DEVMANAGER_WORKTREE` (the worktree root) and
`DEVMANAGER_HOOK_DIR` (the directory the hook runs in). That is why an `after_create` migration can see
the generated `DATABASE_URL` and migrate the branch's own database.

### How a file is built

`env_source` is read from disk and its values have `{placeholders}` expanded — that becomes the
baseline. Then the `env` map is applied as a patch: a key already in the file is **overwritten**, a new
key is **added**. With no `env_source`, the baseline is empty and `env` is the whole file.

## `databases`

A map of logical names you choose (`primary`, `test`, `cache`, …). They are processed in alphabetical
order.

| Field | Meaning |
|---|---|
| `adapter` | `postgresql`, `mongodb`, `sqlite`, `redis`, or a key from `custom_adapters`. The aliases `postgres`, `mongo`, `sqlite3` still work |
| `name_pattern` | pattern for the physical name. Tokens: `{app}`, `{app_name}`, `{branch}`, `{branch_slug}` (the last two are synonyms here). An unknown token is a hard error |
| `copy_from` | clone this existing database instead of creating an empty one. Used **literally** — placeholders are **not** expanded here, so write the exact existing name, never `{app}_development` |
| `migrate_on_up` | parsed and shown by `wop config show`; **runs nothing**. Put migrations in `after_create` |
| `connection` | optional server coordinates, below |

### Adapters

| Adapter | Needs | Notes |
|---|---|---|
| `postgresql` | `createdb`, `dropdb`, `psql` | `copy_from` streams `pg_dump \| psql`, so it works while the source is in use |
| `mongodb` | `mongodump`, `mongorestore` | `copy_from` remaps the namespace |
| `sqlite` | — | a file under the worktree; a `connection` block is a validation error |
| `redis` | `redis-cli` | **does not isolate per branch** — see below |

### `connection`

```yaml
databases:
  primary:
    adapter: postgresql
    name_pattern: "{app}_{branch_slug}"
    connection:
      host: localhost
      port: 5433
      user: postgres
      password_env: MY_PG_PASSWORD   # the NAME of an env var, never the password
```

Every field and the whole block are optional; omitting it behaves as before. Resolution order is
`connection` → the adapter's standard env vars (`PGHOST`, `PGPORT`, `PGUSER`, …) → built-in defaults.
The same resolved connection builds both the creation command and the URL written into `.env`, so the
two can never disagree. `password_env` is read at runtime; `wop` errors and names the variable when it
is unset.

### Redis is not isolated

All branches share one server, and `{database_url_cache}` is that shared address with no namespace in
it. Isolation is a convention the application must follow: prefix every key with
`{db_name_<logical>}`, which resolves to something like `myapp_feature_login_9f2a`. `wop down` and
`wop cleanup` then delete exactly `<that-prefix>:*` plus a `__wop:<prefix>` sentinel. Unprefixed keys
are shared between branches and are never cleaned up.

## `custom_adapters`

```yaml
custom_adapters:
  mysql:
    create: mysql -e "CREATE DATABASE {db_name}"
    drop: mysql -e "DROP DATABASE IF EXISTS {db_name}"
    exists: mysql -e "USE {db_name}" 2>/dev/null                                      # optional
    copy: mysql -e "CREATE DATABASE {db_name}" && mysqldump {source_db_name} | mysql {db_name}  # optional
    url: mysql://root@localhost/{db_name}

databases:
  primary:
    adapter: mysql
    name_pattern: "{app}_{branch_slug}"
```

`create`, `drop` and `url` are required. `copy` is what enables `copy_from`.

## `hooks`

Grouped by service name. Only defined services are accepted. Commands run in that service's `dir`,
unattended, with no TTY.

| List | When |
|---|---|
| `after_create` | after databases are created, before services start |
| `after_up` | after every service has started successfully |
| `before_down` | before `wop down` tears the environment down |

## Placeholders

Expanded in `services.env`, per-service `env`, and in the values inside `env_source` files.

| Token | Value |
|---|---|
| `{app}`, `{app_name}` | `app.name` |
| `{branch}` | the git branch, e.g. `feature/login` |
| `{branch_slug}` | branch with `/` → `-`, case preserved: `feature-login` |
| `{worktree_path}` | absolute path to the worktree root |
| `{<service>_port}` | the port allocated to that service, available to **every** file in the run |
| `{database_url_<logical>}` | connection URL for that database |
| `{db_name_<logical>}` | resolved physical database name |

### `{branch_slug}` means two different things

The same token is sanitised differently depending on where it appears, because env values and database
names have different rules:

- **In env values:** `/` → `-`, case preserved. `feature/Login` → `feature-Login`.
- **In a database `name_pattern`:** lowercased, with both `/` and `-` → `_`. That mapping is not
  reversible (`feature/login` and `feature-login` would collide), so a short hash of the original
  branch name is appended **whenever** slugifying changed the string. Plain names like `main`,
  `develop` and `staging` are left alone.

So `feature/login` gives the env slug `feature-login` and a database named
`myapp_feature_login_9f2a3b1c`. Collisions become improbable, not impossible.
