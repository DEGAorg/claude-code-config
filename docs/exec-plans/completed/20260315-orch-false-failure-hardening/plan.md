# Plan: Orch false failure hardening

**Status:** In progress
**Created:** 2026-03-15

## Requirements

- Review runs even when some items failed — reviews the done items, skips failed ones
- Engine reports partial success clearly (N/M items shipped, K failed)
- Done-file too-small guard warns but doesn't hard-reject (same pattern as no-changes fix)
- SHIP path handles partial completion: ships done items, logs which items failed

## Approach

### 1. Review accepts partial completion

In `orch-review.sh`, change the "all items must be done" gate:
- Count done vs failed vs other
- If any items are still running/ready/queued, exit 1 (not finished yet)
- If all items are done or failed, proceed with review of only the done items
- Log which items are failed and skipped

### 2. Engine reports partial completion

In `orch-engine.sh`, when the wave loop exits:
- If failed > 0 but running=0 and ready=0 and queued=0, log a clear summary
- Proceed to review (which now handles partial completion)

### 3. Relax done-file too-small guard

In `orch-state.sh`, the 20-byte minimum check currently retries and eventually fails the item. Change to: warn and accept. The reviewer will catch garbage done-files — that's what review is for.

### 4. SHIP path handles failed items

The SHIP path currently assumes all items passed. Add a summary line listing any failed items so the operator knows what wasn't shipped.

## Files to touch

| File | Change |
|------|--------|
| `scripts/orch-review.sh` | Accept partial completion — review done items, skip failed |
| `scripts/orch-engine.sh` | Log partial completion summary before review |
| `scripts/orch-state.sh` | Relax done-file too-small guard to warn-and-accept |

## Risks and open questions

- **P2:** Partial SHIP means some work items are missing. The reviewer should note this in its verdict. If critical items failed, reviewer should REVISE.

## Progress log

- [x] Change orch-review.sh to accept partial completion (review done items, skip failed)
- [x] Update orch-engine.sh wave exit to log partial completion summary
- [x] Relax done-file too-small guard in orch-state.sh to warn-and-accept
- [x] Add failed-items summary to SHIP path output

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| Review done items, skip failed | Reject entirely if any failed | Rejecting wastes all the work from done items. Reviewer can assess if failed items are critical. |
| Warn on small done-file | Hard reject | False failures are worse than a garbage done-file. Reviewer catches quality issues. |

## Completion criteria

- [ ] An orch run where 1 item fails still reviews and ships the remaining items
- [ ] `shellcheck scripts/orch-state.sh scripts/orch-engine.sh scripts/orch-review.sh` clean
