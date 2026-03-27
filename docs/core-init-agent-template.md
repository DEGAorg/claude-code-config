# <Project Name>

<!-- Replace this with a one-line description of your project. -->

---

## Repo Map

| Path | Purpose |
|------|---------|
| `src/` | Application source code |
| `tests/` | Test files |
| `docs/` | Documentation |
| `docs/exec-plans/` | Execution plans (active + completed) |

<!-- Update the table above to match your actual directory structure. -->

## Working Conventions

- Language-specific standards load from `~/.claude/rules/` by file type
- Ralph Loop config: `dega-core.yaml` (edit `check_command` for your toolchain)
- Exec plans: `docs/exec-plans/active/<YYYYMMDD-slug>/plan.md`
- Do not push directly to `main` — use feature branches and PRs

## Active Work

Check `docs/exec-plans/active/` for in-progress plans before starting new work.
Each plan is a directory — read `active/<slug>/plan.md`, find the first unchecked
`[ ]` in the Progress log, and continue from there.

## Ralph Loop

Run the outer loop to drive worker/reviewer agents to convergence:

```bash
bash ~/.claude/scripts/ralph-loop.sh <YYYYMMDD-slug>
```

The task-slug must match a directory in `docs/exec-plans/active/`.

## Key References

- Global agent config: `~/.claude/CLAUDE.md` (provider-specific install target)
- Global rules: `~/.claude/rules/` (python, node-typescript, rust, bash, github-actions)
- Global commands: `~/.claude/commands/` (plan, fix-issue, review-pr, cleanup, doc-garden)
- Global scripts: `~/.claude/scripts/` (ralph-loop.sh, plan-advance.sh, ralph-check.sh)
