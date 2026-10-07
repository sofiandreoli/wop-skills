# Troubleshooting

Start from the symptom. Read `<worktree>/<dir>/<service>.log` before forming a theory — the `wop up`
output rarely carries the real error.

---

## A service shows status `stopped` in `wop list`

First read the PID beside it, because it says which of two different things happened:

- **PID blank (`—`)** — `wop stop` was run on it deliberately. `wop restart <branch> <service>` brings it
  back on the same port. Nothing is wrong.
- **PID still showing a number** — the process died on its own or was killed from outside, so `wop` never
  got to clear it. That is the case worth investigating.

1. Read `<worktree>/<dir>/<service>.log`. A crash on boot is there — but a log that ends normally at its
   startup line is evidence too: it means the process was killed from outside, not that it failed.
2. `wop restart <branch> <service>` to try again. It returns before the child is listening, so curl the
   port and retry once after a second before calling it dead.
3. Still dead on the same line? It is the app, not `wop`. The usual causes are a missing dependency
   (an `after_create` hook that failed and did not stop the run) or a migration that never ran, which
   is what `migrate_on_up` not doing anything produces.

## `wop up` fails saying the branch is already checked out

Git refuses one branch in two worktrees. Something else — another `wop` environment, a manual
`git worktree add`, an editor — already holds it.

- `git worktree list` shows who.
- If it is a `wop` environment, `wop list` shows it and `wop down <branch>` frees it.
- To use the worktree that already exists, `cd` into it and run `wop up --here`.

## A port is already in use

1. `wop ports scan` — if it reports no free port, the range is exhausted. Widen `port_range` in
   `.devmanager.yml`.
2. `lsof -nP -iTCP:<port> -sTCP:LISTEN` — if the holder is not one of `wop`'s PIDs from `wop list`,
   something outside `wop` has the port. A stale process from an earlier crash is the common case.
3. A service bound to a different port than `wop` allocated means the app ignores what it was given.
   That is a config problem, not a runtime one — see `wop-configure`, and the `cmd has to accept the port
   it is given` entry in its sharp edges.

## `wop list` shows an environment whose worktree is gone

The registry outlived the directory — usually someone ran `rm -rf` or `git worktree remove` by hand.

`wop cleanup` reclaims it, since its services are already dead. If git still believes the worktree
exists, `git worktree prune` clears git's own record.

## A worktree directory with no registry entry

The inverse of the case above, and the usual residue of a crashed agent or a `git worktree add` by hand:
a sibling directory that looks like a `wop` worktree, but `wop list` has never heard of it.

`wop cleanup` will not touch it — it works from registry entries, not from directories, so a directory
with no entry is invisible to it. The same is true of `--global`: it reaches further across *projects*,
never across unregistered directories.

`git worktree list` says whether git still tracks it. If it does, `git worktree remove <path>` (or
`git worktree prune` once the directory is gone) is the tool; if git does not either, it is just a
directory and removing it is an ordinary `rm -rf` the person should confirm.

This is also the answer when someone says there is leftover junk and `cleanup` reports
`registry is clean, nothing to remove`: the two commands look at different things. Check
`git worktree list`, the sibling directories, and the database server before concluding there is nothing
there.

## `wop down` leaves the worktree on disk

Expected when `wop` did not create it. `wop up --here` records the worktree as one it must never
remove; it stops the services and drops the databases and leaves the directory to its owner.

## An environment an agent abandoned

Status `stopped` with a stale PID still showing, nobody using it.

`wop cleanup` is the right command: it reclaims branches whose services are all dead and skips any branch
still running something, so it cannot cost you a live environment. Add `--global` when the abandoned lane
belongs to another project.

If only *some* of the branch's services are dead, `cleanup` will skip the whole branch by design. Use
`wop restart <branch> <service>` for those.

`wop down all` also clears the abandoned environment, but asks about — and destroys — everything,
including environments still in use.

## The registry was written by a newer schema

`wop` refuses to modify a `registry.json` written by a schema newer than the binary understands. That
means another, newer `wop` on this machine wrote it.

Upgrade `wop` (`brew upgrade wop`). Never hand-edit `registry.json` to get past it — that is how
entries and real running processes get orphaned.

## Databases pile up across branches

Each branch gets its own, named by `name_pattern`. They are dropped by `wop down` and by `wop cleanup`.
Branches torn down with `git` instead of `wop` leave theirs behind.

List them (`psql -l` for PostgreSQL) and match against `wop list`. Anything matching the pattern with
no live environment is an orphan and can be dropped by hand.

## Two branches see each other's data

- **Redis:** expected unless the app prefixes its keys with `{db_name_<logical>}`. `wop` does not
  namespace the Redis URL. See the `wop-configure` skill's sharp edges.
- **Any other adapter:** the app is not reading its database name from the environment. Run
  the `wop-audit` skill — check 2.

## `wop live` exits 1 and that fails something

Usually its contract: it exits `1` when services are running, so the Homebrew formula can refuse to replace
a binary out from under them. `wop stop all` first, then upgrade.

But check `wop --version` before concluding that. `live` was added in v3.0.0, and an older binary exits
`1` with `unknown command: live` — the same code, a completely different meaning.
