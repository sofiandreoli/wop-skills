# wop skills

Agent skills for [`wop`](https://github.com/sofiandreoli/worktree-dev-manager) — a CLI that gives
every Git branch its own isolated development environment with git worktrees: a separate checkout,
its own ports, generated `.env` files, databases and dev servers.

These three skills teach a coding agent to get `wop` running in **your** repo: whether it can work
there at all, what `.devmanager.yml` has to say, and how to drive it day to day.

[![skills.sh](https://skills.sh/b/sofiandreoli/wop-skills)](https://skills.sh/sofiandreoli/wop-skills)

## Install

```bash
# all three
npx skills add sofiandreoli/wop-skills

# or one at a time
npx skills add sofiandreoli/wop-skills --skill wop-audit
```

Works with Claude Code, Codex, Cursor, OpenCode and
[75 more agents](https://github.com/vercel-labs/skills#supported-agents). Add `-g` to install for
every project instead of just this one, and `npx skills update` to pull later changes.

## The skills

| Skill | What it does |
| ----- | ------------ |
| `wop-audit` | Reads your codebase and grades it red/yellow/green against what `wop` needs — hardcoded ports and database names, env files, files a fresh worktree would be missing, and more. Offers to fix the blocking ones, one diff at a time, and writes the report to `docs/wop-readiness.md`. |
| `wop-configure` | Writes the `.devmanager.yml` for your repo — services, port ranges, databases, env files and hooks — then proves it works with a real `wop up` on a throwaway branch. |
| `wop-use` | Runs `wop` for you day to day: bring a branch up, stop or restart a service, tear an environment down, and diagnose a service that will not start. |

Run them in that order the first time. After that, `wop-use` is the one you keep.

The first two read your code and propose changes to it; they ask before writing anything. What
`wop-audit` will and will not do on its own is spelled out in its `## Consent` section.

## Requirements

The skills drive the `wop` binary, so it has to be installed:

```bash
brew install sofiandreoli/tools/wop
```

macOS and Linux. Windows is not supported yet.

## License

MIT — see [LICENSE](LICENSE).
