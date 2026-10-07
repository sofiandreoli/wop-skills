# Command reference

Run from the project root holding `.devmanager.yml`, or any subdirectory of it. `wop up --here` is the
exception and runs from inside an existing worktree.

`wop` with no arguments prints this list. The `--help` flag does not: it is consumed by the flag
parser, which prints only the flag usage.

## Creating and tearing down

### `wop up <branch>`

Creates the worktree, allocates a free port per service, writes the env files, creates the databases,
runs `after_create` hooks, starts each service, runs `after_up`, and registers the PIDs and ports.

The worktree is a sibling of the repo root: `<repo-parent>/<app.name>--<branch with / as ->`, with `_`
and a short hash appended whenever rewriting the branch name changed it — so every branch containing a
`/` gets one. `feature/login` becomes `my-app--feature-login_9f2a3b1c`; `main` stays `my-app--main`.
The hash keeps `feature/login` and `feature-login` from sharing a directory. `wop up` prints the path it
used; prefer that over reconstructing it.

Fails if another worktree already holds the branch — git refuses the same branch twice. Use `--here`.

### `wop up --here`

Everything above except creating the worktree. Run it from inside a worktree another tool created. The
branch comes from the current `HEAD`, and the environment registers under the repository's **main**
checkout, so it appears in `wop list` alongside the others and is swept by `wop down all`.

`wop` records that it did not create this worktree: teardown stops the services and drops the
databases, and leaves the directory on disk.

### `wop down <branch>`

**Destructive.** Runs `before_down` hooks, stops the registered processes, removes the worktree, drops
that branch's databases, and clears the registry entry. Uncommitted work in the worktree is lost.

It does **not** delete the git branch. After a teardown the branch ref is still there; removing it is a
separate `git branch -d <branch>`.

### `wop down all [--global] [-y]`

Tears down every environment of the current project; `--global` reaches every project on the machine.
Asks for confirmation unless `-y` / `--yes` is given — so it needs a terminal. With no TTY it cannot
prompt, and `-y` is only appropriate once the person has actually agreed; prefer naming the branch
(`wop down <branch>`) when there is one environment, which asks nothing.

`--global` selects by registry entry, not by directory: it reaches environments `wop` registered,
wherever they are, and never a stray directory that has no entry.

If an environment exists on a branch literally named `all`, that branch wins; `-y` or `--global` forces
the sweep instead.

## Running services

### `wop stop <branch>`

Kills (`-9`) every service for the branch. The worktree, the databases and the registry entry stay; the
PID is cleared. Reversible with `restart`.

### `wop stop <branch> <service>`

The same, scoped to one service name from `.devmanager.yml`.

### `wop stop all [--global] [-y]`

Stops every service of the current project; `--global` for every project. Same `all`-branch rule as
`down all`.

### `wop restart <branch>`

Restarts the stopped services for the branch, reusing the stored `cmd` and the port already allocated —
so URLs that worked before keep working.

### `wop restart <branch> <service>`

The same, for one service.

## Inspecting

### `wop list`

Active environments, grouped by project: branch, service, port, PID, status. The roster for parallel work.

Read PID and status together. A blank PID (`—`) with status `stopped` means `wop stop` was run
deliberately, and `wop restart` brings it back. A *stale* PID with status `stopped` means the process died
or was killed from outside — `wop` never got to clear it.

### `wop live`

Reports which services are really running and **exits `1` if any are**. Built for scripting — the
Homebrew formula runs it before replacing the binary.

**Added in v3.0.0.** An older binary prints `unknown command: live` and exits `1` as well, which is the
same exit code it would use for "services are running" — so check `wop --version` before trusting that
`1`.

### `wop config show`

Prints the parsed `.devmanager.yml` for the current directory. Use it to check that the config is valid
and to read the resolved database names.

### `wop ports scan`

Prints the first free port in each service's `port_range`. Shows whether a range is exhausted before a
`wop up` discovers it.

### `wop --version`

Prints the embedded version string.

## Setting up

### `wop init`

Writes a starter `.devmanager.yml` in the current directory, with `app.name` set to the current
directory's name — check it, it is often not the project's name. Edit the rest to set each service's `cmd`
and `port_range`, and note that the generated `port_range` overlaps itself if you copy the block for a
second service. See the `wop-configure` skill.

### `wop cleanup [--global]`

Reclaims every branch of the current project whose services are **all** dead: removes the worktree,
drops the databases, and clears the registry entries. `--global` does the same for every project on the
machine.

A branch with even one service still running is skipped entirely, entries included — a stopped service
beside a running one keeps the `cmd` and port that `wop restart <branch> <service>` needs. So `cleanup`
is not the way to revive one dead service; `restart` is.

It takes no `-y`, because it never touches anything running and so has nothing to confirm.

With nothing to reclaim it prints `registry is clean, nothing to remove` — including when the project has
live environments it deliberately skipped. The message is about what was *removed*, not about what is
registered, so do not report it as "there were no environments".

The right command for environments an agent or a crashed session left behind. **Added in v3.0.0**:
before that, `cleanup` took no flags, was always machine-wide, and did prune a stopped service out of
a running environment (issue #108).

Without `--global` it needs a `.devmanager.yml` to resolve which project it is in, the same as
`wop down all`. `--global` works from anywhere.

## Where state lives

The registry is a single `registry.json` under `~/.config/devmanager` — or under `WOP_STATE_DIR` when
that variable is set, which relocates the whole thing and is how a test or a sandbox keeps off your real
environments. It is tagged with the schema version that wrote it. A registry written by a newer schema than the installed binary understands is never
modified — upgrade `wop` rather than editing the file.
