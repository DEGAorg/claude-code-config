# Canon TUI Wiring

How the Canon TUI (aka "conductor-view", a Toad fork at `DEGAorg/conductor-view`) accesses Canon knowledge and commands. **This is a separate repo** — it does not automatically inherit anything from `claude-code-config`.

## Two surfaces the TUI needs

1. **Commands** — exercise Polymarket and Canon operations.
2. **Skills** — display agent-facing knowledge (e.g. show the user what `polymarket` explains, or render help inside the TUI).

Both are already installed globally by `/apply-core` from this repo. The TUI only needs to read from the installed locations.

## Command surface — `canon-cli`

Invoke as a subprocess; parse the JSON envelope from stdout.

- **Binary:** `~/.degacore/bin/canon-cli` (symlink created by `/apply-core`).
- **Contract:** every command returns `{"ok": true, "data": <result>}` on stdout, or `{"ok": false, "error": "<message>"}` on stderr with exit 1.
- **Auth:** set `POLYMARKET_PRIVATE_KEY` env var before invoking auth-gated commands. Read-only commands (`market`, `help`) don't need it.
- **Reference:** full command list in `canon/skills/canon-cli.md` (in this repo) or `~/.degacore/config/skills/canon-cli.md` (globally).

Minimum TUI integration:

```
exec("canon-cli", ["market", "search", query], { env: { POLYMARKET_PRIVATE_KEY: ... } })
  .then(out => JSON.parse(out.stdout).data)
```

Handle the `{ ok: false, error }` case by surfacing the error string verbatim — messages are already human-readable and actionable.

## Skill surface — knowledge display

After `/apply-core`, these files exist on disk:

- `~/.degacore/config/skills/canon-cli.md` — agent-facing command reference with intent→command map.
- `~/.degacore/config/skills/polymarket.md` — platform mechanics, fees, USDC.e-only rule, common mistakes.
- `~/.degacore/config/skills/<other>.md` — any other skills `/apply-core` installs.

**Rendering path:** read the file, parse YAML frontmatter (see `canon/cli/commands/help.ts:parseFrontmatter` for a reference parser), display the markdown body. Frontmatter fields the TUI cares about: `name`, `description`, `domain`, `version`.

Alternative: shell out to `canon-cli help <name>` and render the JSON `data.content` field. This gets the same markdown but lets the CLI own the file resolution (project-local vs global fallback).

## What the TUI must NOT do

- **Do not vendor a copy** of `canon-cli.md` or `polymarket.md` into the TUI repo. These get edited in `claude-code-config` and installed on every `/apply-core`. A vendored copy will silently drift.
- **Do not read from a `claude-code-config` checkout path** — users running the TUI won't have that repo locally. Read from `~/.degacore/config/skills/`.
- **Do not reimplement the CLI.** The CLI is the contract — call it as a subprocess. Reimplementing order signing / approvals / the Uniswap swap path in the TUI repo is a maintenance liability and a signing-key surface we don't want duplicated.

## When to update this doc

- A new command is added to `canon-cli` → add it to `canon/skills/canon-cli.md`. No TUI change needed if the TUI introspects via `canon-cli help`.
- The install destination moves (unlikely) → update `commands/apply-core.md` and this file.
- The JSON envelope contract changes (breaking) → treat as a TUI API break; version the CLI and coordinate.

## Open items for the TUI side

These need to be decided in the conductor-view repo, not here:

- Caching strategy for skill content (re-read on each render, or cache in memory).
- Whether the TUI should spawn its own burner wallet or require `POLYMARKET_PRIVATE_KEY` to be pre-set.
- Presentation: raw markdown vs rendered blocks vs command palette with intent→command hints lifted from `canon-cli.md`.

## Related

- Install manifest: `commands/apply-core.md` (search `canon/skills/` to see what gets installed).
- Help implementation: `canon/cli/commands/help.ts` — reference for frontmatter parsing and project-local / global fallback.
- Dual-source rule: `canon/AGENTS.md` → "Where skill knowledge lives".
