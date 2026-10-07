# wop readiness

Audited `<repo name>` on <YYYY-MM-DD> against the eight checks in the `wop-audit` skill.
Re-run the `wop-audit` skill.

**Verdict:** <one sentence: can this repo use `wop` today, and if not, what is the shortest path.>

| | Check | Grade |
|---|---|---|
| 1 | Port binding | 🔴 / 🟡 / 🟢 |
| 2 | Database identity | |
| 3 | Env files | |
| 4 | Required but ignored files | |
| 5 | Worktree hostility | |
| 6 | Fixed OS-level resources | |
| 7 | Scripted setup | |
| 8 | Existing `.devmanager.yml` | |

---

## 🔴 Blocking

### <short title>

- **Where:** `path/to/file.rb:42`
- **Found:** `<the exact string>`
- **Why it blocks:** <the concrete failure — which command fails, or which two branches collide on what>
- **Fix:** <the substitution, or "needs a decision: ..." when it is not mechanical>
- **Status:** one of —
  - `not applied` — offered, declined or not yet raised
  - `applied on <date>` — with the diff below it, so a reader in a month sees what changed
  - `blocked on approval` — mechanical, but nobody was available to approve it
  - `needs a decision` — not a substitution; names the choice to be made
  - `red by design` — correctly left as it is, with the reason; does not count as outstanding
  - `yellow by design` — the fix landed and deliberately stops short of green, e.g. an env read that
    keeps a working literal fallback. Says "finished", not "half done"

<Repeat per finding. Drop this section when there are none.>

## 🟡 Worth fixing

### <short title>

- **Where:** `path/to/file:line`
- **Impact:** <what is slower, manual, or shared>
- **Suggestion:** <what to do, and whether it can wait>

## 🟢 Already fine

- <check name> — <the one fact that makes it fine, e.g. "port read from `PORT` in `server.ts:8`">

---

## For `wop-configure`

What the next step needs, gathered while auditing:

- **Services:** <name → directory → start command → a free port range>
- **Databases:** <logical name → adapter → whether an existing database should be copied>
- **Setup commands for `after_create`:** <the real, unattended install/migrate/seed chain>
- **Env template:** <path to use as `env_source`, or "none — write the `env` map directly">
- **Files a fresh worktree will be missing:** <and how a hook recreates each>
