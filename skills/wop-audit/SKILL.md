---
name: wop-audit
description: Use when someone asks whether a repository can work with wop, whether it is ready for per-branch git-worktree environments, what has to change before adopting wop, or why two branches end up sharing a port or a database. Also use before configuring .devmanager.yml in a repo for the first time.
---

# Audit a repo for wop

## Overview

`wop` gives every branch its own worktree, ports, env files and databases. It can only do that for
values the repo reads from its environment. Anything baked into the source — a literal port, a
database name in `database.yml`, a file that exists only in the main checkout — defeats it.

The dangerous failure is not a crash. It is `wop up` succeeding while two branches quietly write to
one database.

## Grades

Grade by consequence, never by taste.

| Grade | Meaning |
|---|---|
| 🔴 red | `wop up` fails, **or** it succeeds without real isolation (branches sharing a port, a database, or a file) |
| 🟡 yellow | works, but needs manual steps, is slow, or silently shares a resource |
| 🟢 green | ready |

A check's grade is its **worst** finding. One red in a check makes the check red, however many greens
sit beside it; list the lesser findings under it rather than averaging them away.

## Procedure

1. **Detect the stack**, because it decides where to look for everything below. Not just the language —
   the framework, from the files that give it away: `config/database.yml` plus `config/master.key` plus
   `Procfile` is Rails; `manage.py` is Django; `prisma/schema.prisma`, `knexfile.js` or `ormconfig.json`
   name the ORM; `docker-compose.yml`, `Makefile`, `bin/` and `scripts/` hold the setup steps. Note the
   project's real name too — the root directory's name is often not it.
2. **Run all eight checks** in `references/checks.md`. Run every one. Never stop at the first red —
   a partial audit sends someone to fix one thing and hit the next on the following try.
3. **Grade each check** and keep the evidence: file, line, and the exact string found.
4. **Print the traffic light in chat.** Reds first with their evidence, then yellows, then one line
   for what is already green.
5. **Write the full report** to `docs/wop-readiness.md` in the audited repo, using
   `assets/report-template.md`. Create `docs/` if it does not exist. "The audited repo" is the checkout
   you are standing in, even when that is a worktree or a scratch copy — never the primary checkout of
   some other directory.
6. **Offer the fixes.** For each red that has an entry in `references/fixes.md`, show the exact diff and
   apply it as the **Consent** section below allows — which depends on whether anyone is reachable and
   what they have already approved.
7. **Re-run the checks** the applied fixes touched, and update the report. Then say that the fixes have
   to be **committed**: a worktree is built from a commit, so anything still sitting in the working tree
   does not reach it. `wop up` would create a worktree running the old code, and the fixes would look
   like they did not work. Committing is the user's call — say it, do not do it.
8. **Hand off.** Say where things stand and that the `wop-configure` skill is the next step. Some reds are not
   mechanical — committed secrets, a setup that needs a human — and waiting for those to disappear
   would mean never handing off. When reds remain, hand off anyway and name them: writing
   `.devmanager.yml` is still worth doing, and `wop-configure` re-reads the report and will say so.

## Consent

Every fix changes how someone's app boots, in their own repository. Two properties decide how a fix may
be applied, so classify each one before raising it:

- **Reversible** — a pure substitution that keeps the old literal as its default, so running the app
  outside `wop` behaves exactly as it does today. Undoing it is one edit.
- **Everything else** — it destroys something, or it decides something. Untracking a file, rewriting
  history, choosing between two valid designs, inventing config the repo does not have.

Then the four situations, which cover every run:

| Situation | Reversible fixes | Everything else |
|---|---|---|
| Someone is there, no blanket approval | one diff, one yes, one fix | same, and name the consequence before asking |
| Someone is there and pre-approved everything | **may be applied together**, then reported | raise individually anyway |
| Nobody is reachable | apply, and say so in the report | defer to the report, never apply |
| They saw it and handed the choice back | **choose the reversible option** | — |

**Blanket approval covers the reversible class and nothing more.** Someone cannot consent to a finding
they have not seen. But it does mean the reversible fixes go in as a batch rather than as twenty
questions — a literal reading that demands a separate yes for each one wastes exactly the patience they
just told you they do not have.

**"Whatever you think" is a delegation, not a decision.** When someone has seen the consequence spelled
out and responds by handing the choice back, the reason for caution has changed — they *could* have
consented — but your judgement has not. Take the option that can be undone, say which one you took and
why, and leave the irreversible one in the report as outstanding. A choice you were asked to make is
still yours to make well.

**Time pressure is legitimate input into which option you pick, and no input at all into whether you
have consent.** "Twenty-five minutes to a demo" is a real reason to prefer the fast reversible path over
the thorough irreversible one. It is not a reason to treat silence as a yes.

**Never commit.** Not even when the fixes are obviously right and the person is in a hurry. Say that
committing is needed and why — see step 7 — and leave it to them.

A destructive fix often has an additive half that carries no cost: committing a `.env.example` is not
untracking `.env`, and `mkdir -p tmp` is not changing a pidfile. Apply the additive half when it stands
on its own, and keep the rest deferred.

**Red flags — these are inventing consent, stop:**

- "They approved the first one, so they mean all of them"
- "This one is obvious, no need to show the diff first"
- "It's a one-line change, it doesn't need its own yes"
- "They didn't answer, so they probably meant yes"
- "I'll commit it so they can see it working"

## Not in scope

This skill does not restructure the application, write migrations, or introduce a config library. It
also does not **create application files the repo does not have** — a missing `package.json`, lockfile,
`Gemfile`, HTML entry point or dependency declaration is a finding, not a gap for you to fill. Inventing
one produces something that looks fixed and is somebody else's guess about their app.

Nor does it write `.devmanager.yml`. That is the `wop-configure` skill, which runs after this and verifies its
own work with a real `wop up`.

Those findings stay in the report with file, line and what to change. Say that plainly instead of
starting a large refactor — and never report a red as fixed when all that happened was writing it down.
