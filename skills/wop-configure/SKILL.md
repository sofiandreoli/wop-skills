---
name: wop-configure
description: Use when someone needs a .devmanager.yml written or corrected for their repository, is setting up wop for the first time, asks how to declare services, ports, databases, env files or hooks for wop, or when wop config show rejects their config or wop up fails because the config is wrong.
---

# Configure wop for a repo

## Overview

`.devmanager.yml` at the project root tells `wop` what to run per branch: services and their port
ranges, databases, how to build each `.env`, and the hooks that make a fresh worktree bootable.

The deliverable is not a file that parses. It is a file that survives a real `wop up`.

## Procedure

1. **Start from the audit.** Read `docs/wop-readiness.md` if it exists — its "For `wop-configure`"
   section is written for this step. Reports written before these skills were renamed head that
   section "For `/wop:configure`"; accept either, the contents are the same. If anything red is still
   outstanding, say so and offer the `wop-audit` skill before continuing; a config cannot compensate
   for a hardcoded port. With no report, do a short scan of your own for services, start commands,
   databases and setup steps.
2. **Generate the skeleton** with `wop init`, then edit its output. Two things about what it writes:
   - `app.name` is just the current directory's name. Check it and correct it — it becomes the worktree
     directory name *and* the `{app}` token in database names, so a wrong one is wrong everywhere.
   - its single service gets `port_range: [3000, 3100]`. That is not a template for a second service:
     copy the block and the ranges overlap, which `wop config show` rejects.
   - it scaffolds a postgres `databases: primary:` block whether or not the app has a database.
     **Delete it when the app has none.** Left in place it validates, and `wop up` cheerfully creates a
     per-branch database nothing connects to — plus a dependency on `createdb`/`psql` the project never
     had.
3. **Declare the services.** Per service: `dir` (relative to the worktree root), `cmd` (the real dev
   command, which runs through `sh -c`), and a `port_range` that overlaps no other service.
4. **Declare the databases, if there are any.** The `databases` key is **optional** — an app with no
   database gets no block at all, and `wop config show` reports `0 logical database(s)`. Decide from
   evidence: a client library in the dependencies, a connection string in the env template, an actual
   query. When there are databases, give each a logical name with `adapter`, `name_pattern`, and
   `copy_from` when the branch should start from real data instead of empty.
5. **Build the env.** Decide shared (`env_source` / `env` directly under `services`), per service, or
   both. Prefer `env_source` pointing at the repo's committed template, patched by a small `env` map
   holding only what varies per branch.
6. **Write the hooks.** Turn the repo's actual setup chain into `after_create`, keyed by service
   name. Migrations go here — `migrate_on_up` runs nothing.
7. **Validate statically:** `wop config show`, then `wop ports scan`. Know what this does *not* cover:
   `config show` prints services, ranges, databases and hooks, but **not the per-service `env` maps**,
   and its `env source` line reads empty per service even when a shared one is set. So the thing you most
   want to check — did the placeholders land where I think? — is invisible here. It becomes visible only
   as the generated `.env` files, after step 8.
8. **Smoke test for real.** See below. This is the step that matters.
9. **Hand off** to the `wop-use` skill.

Read `references/sharp-edges.md` before writing the file, and `references/devmanager-reference.md`
for any field or placeholder.

## The smoke test

Static validation proves the YAML parses. It cannot tell you that the app ignores `PORT`, that a hook
fails, or that two services fight over a port. Only a real run does.

Say what it will do — it runs the full install, and creates real local databases when the config
declares any — and get a yes. Approval can be given ahead of time: a standing "go ahead and run what you
need" covers this, and an unattended run that *has* that approval should take it, because the whole
point of the step is that static checks prove nothing. Only with no approval and nobody to ask do you
run the static checks, stop, and say plainly that the config is unverified and which of the failures
below remain possible.

**Commit first.** A worktree is built from a commit. `.devmanager.yml` is read from where `wop` runs, so
an uncommitted config works — but any uncommitted application change is absent from the worktree, and the
smoke test then exercises the old code. If the audit's fixes are still unstaged, say so and stop short of
the smoke test rather than testing something that is not what will run.

**Use two branches, not one.** The point of `wop` is that the second branch does not disturb the first,
and the failures that matter only appear then: a port that was free once, cross-service URLs wired to
the wrong branch's service, a database name that collides. A one-branch test is the weak version of the
test this step exists for.

```bash
wop up wop-smoke-test
wop up wop-smoke-test-2
```

Each creates a worktree, writes the env files, creates real databases, runs `after_create`, and starts
the services. Then:

- `wop list` — every service of both branches has a PID and a port, and **no port appears twice**. This
  catches `wop` handing out a duplicate. It does **not** catch the failure that actually happens, below.
- **Check the port each process says it bound, not just that something answered.** `wop list` prints the
  port `wop` *allocated*; a service that ignores it and falls back to its hardcoded default binds a
  different one. Then `curl -o /dev/null -w '%{http_code}'` on branch 2's allocated port returns `200`
  from **branch 1's** service, and every green light lies. So read the response body, or the
  `api on <port>` line in `<worktree>/<dir>/<service>.log`, and confirm the number matches what `wop`
  allocated for *that* branch. A bare status code is not evidence here.
- Read the generated env files — `<worktree>/.env` and each `<worktree>/<dir>/.env`. This is the only
  place the placeholders become visible. Check that branch 2's cross-service URLs point at **branch 2's**
  ports, not branch 1's.
- If the config declares databases, the two branches' database names differ.
- On any failure, read `<worktree>/<dir>/<service>.log`. That file holds the real error; the `wop up`
  output usually does not.

Always tear down both, including when it failed:

```bash
wop down wop-smoke-test-2
wop down wop-smoke-test
```

Then verify the teardown against the system, not against `wop list` alone — `wop list` being clean is not
the same as nothing being left behind, and it is global across every project, so it is noisy evidence:

| Check | Expect |
|---|---|
| `wop list` | neither smoke-test branch |
| `git worktree list` | no smoke-test worktree |
| `git branch` | **`wop down` does not delete the branch** — remove them with `git branch -D` |
| the database server (`psql -l`), when databases are declared | no database matching `name_pattern` for those branches. With no `databases` block there is nothing to check — do not report an empty list as a successful drop |

**Do not report the config as working on the strength of `wop config show` alone.** If the user declines
the smoke test, say explicitly that the config is unverified and name what remains untested.

## Common mistakes

| Mistake | What happens |
|---|---|
| Overlapping `port_range`s | `wop config show` rejects the config outright |
| Expecting `migrate_on_up: true` to migrate | it is parsed and displayed, and runs nothing |
| `env_source` written relative to the worktree | the file is resolved from where `wop` runs — the main repo root |
| A plaintext password under `connection` | `.devmanager.yml` is committed; use `password_env` |
| `connection` on a `sqlite` database | validation error — sqlite has no server |
| A `hooks` key that is not a service name | validation error |
| Assuming Redis isolates per branch | it does not; keys must be prefixed with `{db_name_<logical>}` |
