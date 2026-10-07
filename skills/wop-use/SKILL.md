---
name: wop-use
description: Use when someone wants to run wop in a repo that already has a .devmanager.yml — bringing a branch up, stopping or restarting a service, tearing an environment down, listing what is running, finding a worktree's port, cleaning up leftovers, or working out why a service will not start or a port is taken. Also use when running several agents in parallel on one repo.
---

# Run wop

## Overview

The repo is configured; this is the day-to-day. Take the intent, pick the commands, run them, read
the output, and report what happened. Do not explain the CLI unless asked — do the work.

Every command runs from the project root holding `.devmanager.yml`, from any subdirectory of it. The
one exception is `wop up --here`, which is meant to be run from inside an existing worktree.

Full command table in `references/commands.md`. Symptom-to-cause in `references/troubleshooting.md`.

## Intent → command

| They want | Run |
|---|---|
| work on a branch | `wop up <branch>` |
| work in a worktree something else already created | `wop up --here`, from inside it |
| see what is running | `wop list` |
| free up CPU, keep the environment | `wop stop <branch>` |
| start it back up | `wop restart <branch>` |
| stop one service, keep the rest | `wop stop <branch> <service>` |
| be done with the environment | `wop down <branch>` — destructive, see below. It does **not** delete the git branch |
| clear out everything for this project | `wop down all` — for a single environment prefer `wop down <branch>`: narrower, and it needs no `-y` |
| sweep what is already dead | `wop cleanup` (this project) / `wop cleanup --global` (all projects) |
| know which port a branch got | `wop list` |
| check the config | `wop config show` |

## Confirm before destroying

`wop down <branch>` stops the services, **removes the worktree, and drops that branch's databases**.
Uncommitted work in the worktree goes with it.

Before running it: name the worktree path and the databases that will be dropped, and get a yes. For
`wop down all`, say how many environments are in scope. For `--global`, say that it reaches every
project on the machine, not just this one.

The one exception where the directory survives is a worktree `wop` did not create (`up --here`): it
stops the services and drops the databases, and leaves the directory alone.

`wop down` also leaves the **git branch** in place. "I'm done with this branch" usually means the branch
too, so say that `git branch -d <branch>` is the separate, manual step.

**The three are not interchangeable:**

- `stop` — kills the processes. Worktree, databases and registry entry stay. Reversible with `restart`.
- `cleanup` — reclaims branches where **every** service is already dead: worktree, databases and
  entries. A branch with even one service running is left entirely alone. Safe by construction, since
  it never touches anything live.
- `down` — destroys, running or not.

When unsure which one someone means, assume the reversible one and say so.

`cleanup` covers the current project; `--global` extends it to every project on the machine. Because it
only ever reclaims branches that are already fully dead, `--global` needs no confirmation — unlike
`down all --global`, which kills running services and does.

One thing it will not do: bring back a single stopped service. `cleanup` skips its whole branch while a
sibling runs, so reviving that one service is `wop restart <branch> <service>`.

## Diagnose from evidence

In order, before forming a theory:

1. `wop list` — the registered branch, service, port, PID and status. Read the two together:

   | PID | Status | What happened |
   |---|---|---|
   | a number | `running` | fine |
   | `—` | `stopped` | someone ran `wop stop` deliberately → `wop restart` brings it back |
   | a number | `stopped` | it died on its own, or was killed from outside; the PID is stale |

   Do not read a missing PID as a crash. `wop stop` is the thing that clears it; a crash leaves it behind.

2. `wop live` — which services are really running; exits `1` if any are. **It arrived in v3.0.0**, and
   an older binary prints `unknown command: live` and also exits `1` — the same exit code it uses for
   "services are running". So read the output, not just the exit code: `unknown command` means the
   binary is too old. Don't gate on `wop --version` alone, because a build from source prints
   `0.0.0-dev`, which compares against no release at all.
3. `<worktree>/<dir>/<service>.log` — the real error, when there is one. A process killed from outside
   leaves a perfectly normal log ending at its startup line: that means killed, not failed to boot.
4. The registry — what `wop` believes, when it disagrees with reality. It lives at
   `~/.config/devmanager/registry.json` **unless `WOP_STATE_DIR` is set**, which moves it wholesale.
   Check that variable before reading the default path, or you will be reading a file this `wop` never
   touches.

Never assert a cause with the log file unread — but read a clean log as evidence in itself.

After a `wop up` or `wop restart`, `wop` returns before the child is listening. Curl the port, and retry
once after a second before reporting a service as dead.

Read-only commands (`list`, `live`, `config show`, `ports scan`) can be run freely. Everything that
starts, stops or removes something is worth a word first.

## Parallel agents

The reason the isolation exists: one worktree per agent, so they cannot collide on ports, clobber each
other's `.env`, or corrupt a shared database.

- One `wop up <branch>` per agent, each agent working inside its own worktree path.
- `wop list` is the roster — it groups by project and shows every branch's ports and PIDs.
- Agents that died without tearing down leave entries with status `stopped` and a stale PID. `wop cleanup`
  reclaims every lane whose services are all dead, and leaves alone any lane still running something.
- Worktrees are siblings of the repo root, named `<app.name>--<branch with / as ->`, **plus `_` and a
  short hash whenever rewriting the branch name changed it** — which is every branch containing a `/`.
  So `feature/login` in `/projects/my-app` lands at `/projects/my-app--feature-login_9f2a3b1c`, while
  `main` lands at `/projects/my-app--main`. Take the path from what `wop up` prints rather than
  building it by hand.
