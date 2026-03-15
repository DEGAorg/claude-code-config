# Plan: Dashboard viewport uses flexGrow for adaptive sizing

**Status:** In progress
**Created:** 2026-03-15

## Requirements

The worker/reviewer output viewport in the orchestrator dashboard shows only a
few lines of code because it's hardcoded to 35% of terminal height. Switch to
Ink's `flexGrow` layout so the detail panel fills all remaining space after the
session table renders at its natural height.

## Approach

Remove the fixed percentage calculation from `session-detail.tsx` and use
`flexGrow={1}` on the detail panel's outer `<Box>`. The session table already
has a natural height (header + N item rows), so it doesn't need a fixed
allocation. The `orchestrator-app.tsx` wrapper needs a `height="100%"` on
the outermost Box so flexGrow can expand to fill the terminal.

Key constraint: `outputLines` is already sliced to 200 in the parent — that
cap stays. The visible slice should fill whatever space flexGrow gives us
rather than being capped by `maxLines`.

## Files to touch

| File | Change |
|------|--------|
| `scripts/terminal-ui/src/session-detail.tsx` | Remove `maxLines` percentage calc, use `flexGrow={1}` on outer Box, remove `useStdout` import |
| `scripts/terminal-ui/src/orchestrator-app.tsx` | Add `height="100%"` to outermost Box so flex layout fills terminal |

## Progress log

- [x] Update `orchestrator-app.tsx` outermost Box to use `height="100%"` so flexGrow children can expand (deps: none)
- [x] Refactor `session-detail.tsx` to remove percentage-based maxLines and use `flexGrow={1}` with `overflow="hidden"` on the outer Box (deps: 1)
- [ ] Build the terminal-ui to verify TypeScript compiles cleanly (deps: 1, 2)

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| flexGrow over dynamic calc | Calculate table height from items.length | flexGrow is simpler, Ink handles the math, works for any item count |
| Keep 200-line cap in parent | Move cap to detail | Parent already does this; detail just renders what it gets |

## Completion criteria

- [ ] `pnpm run build` succeeds in `scripts/terminal-ui/`
- [ ] Detail panel fills remaining space below the session table
- [ ] No TypeScript errors
