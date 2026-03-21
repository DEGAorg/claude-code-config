# Plan: Sync issue body — check off progress log and completion criteria

**Status:** In progress
**Created:** 2026-03-20

## Requirements

- When a plan item passes review (SHIP), check off its `- [ ]` checkbox in the issue body progress log
- When a plan ships, update `**Status:** Draft` (or any status) to `**Status:** Completed` in the issue body
- When a plan ships, check all `- [ ]` items in the Completion criteria section
- Issue body edits use `gh issue edit --body` with the updated markdown
- Edits are idempotent — re-running doesn't break already-checked items
- If body parsing fails (someone edited the issue manually), log a warning and continue

## Approach

Add two functions to `scripts/gh-plan-sync.sh`:

1. `update_progress_checkbox` — called during `review` event. Fetches the issue body, finds the Nth `- [ ]` line in the Progress log section (matching by item description substring), replaces with `- [x]`, writes back.

2. `update_body_on_ship` — called during `ship` event. Fetches the issue body, replaces `**Status:**` line with `**Status:** Completed`, checks all `- [ ]` in the Completion criteria section, writes back.

Both use `gh issue edit --body "new body"` to write the updated markdown.

## Files to touch

| File | Change |
|------|--------|
| `scripts/gh-plan-sync.sh` | Add `update_progress_checkbox` and `update_body_on_ship` functions, call from review/ship handlers |

## Progress log

- [x] Add `update_progress_checkbox` function to `gh-plan-sync.sh` — fetch body, find matching item in Progress log, check it off, write back via `gh issue edit`
- [ ] Add `update_body_on_ship` function to `gh-plan-sync.sh` — update Status field to Completed, check all Completion criteria items (deps: 1)
- [ ] Test: run an orchestrated plan, verify progress log items get checked as each item ships, verify Status and Completion criteria update on final SHIP (deps: 1, 2)

## Completion criteria

- [ ] Progress log checkboxes in the issue body update as items complete
- [ ] Status field changes to `**Status:** Completed` on SHIP
- [ ] All Completion criteria checkboxes get checked on SHIP
- [ ] If body parsing fails, warning is logged but orchestrator continues
- [ ] shellcheck and shfmt clean
