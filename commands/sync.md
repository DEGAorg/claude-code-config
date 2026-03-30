# Sync Plan State

@description Reconcile local orchestrator state with GitHub Issues — fetch open plans, flag drift, clean up stale state.

Fetch all open plan issues from GitHub and reconcile them with local
orchestrator state. Run this at session start or when resuming work
after a break.

Execute every step below sequentially. Do not stop or ask for
confirmation unless a finding requires a judgment call.

## 1. Check prerequisites

Verify `gh` is installed and authenticated:

```bash
bash scripts/ensure-gh.sh
gh auth status
```

If auth fails, tell the user to run `gh auth login` and stop.

Read `dega-core.yaml` to check for `github.sync`. If `github.sync`
is not `true`, inform the user that GitHub sync is not enabled for
this project and stop. The local plan workflow still applies.

## 2. Resolve repo

Determine the target repo in this order:

1. `github.repo` in `dega-core.yaml`
2. Auto-detect from `gh repo view --json nameWithOwner`

If neither resolves, stop with an error.

## 3. Fetch open plan issues

List all open issues with any `plan:*` label:

```bash
gh issue list --repo <REPO> --label "plan:draft" --json number,title,labels,updatedAt
gh issue list --repo <REPO> --label "plan:active" --json number,title,labels,updatedAt
gh issue list --repo <REPO> --label "plan:review" --json number,title,labels,updatedAt
```

Combine results (deduplicate by issue number). Present a summary table:

```
| # | Title | Label | Updated |
```

If no open plan issues exist, say so and stop.

## 4. Check local orchestrator state

Look for local state directories in `.orchestrator/plans/`:

```bash
ls -d .orchestrator/plans/*/ 2>/dev/null
```

For each local plan directory, check if a `state.json` exists and
what status it records (running, completed, failed).

## 5. Flag drift

Compare GitHub state with local state and report discrepancies:

### 5a. Orphaned local state

Local plan directories in `.orchestrator/plans/` with no matching
open GitHub Issue. These are leftover from completed or abandoned
runs. Recommend cleanup:

```
Orphaned local state: .orchestrator/plans/<slug>/
  No matching open issue found. Safe to remove with: rm -rf .orchestrator/plans/<slug>/
```

### 5b. Stale labels

Issues labeled `plan:active` or `plan:review` but with no local
orchestrator state (no `.orchestrator/plans/<slug>/` directory).
The orchestrator finished or was interrupted without updating GitHub.
Recommend label correction:

```
Stale label: Issue #42 "Add auth endpoint" is labeled plan:active but has no local state.
  The orchestrator may have completed or been interrupted.
  Recommend: review issue and update label to plan:completed or plan:draft.
```

### 5c. Closed issues with local state

Issues that are closed on GitHub but still have local state
directories. Recommend cleanup:

```
Closed with local state: Issue #42 is closed but .orchestrator/plans/<slug>/ still exists.
  Safe to remove.
```

## 6. Offer reconciliation

For each drift finding, suggest a concrete action. If there are
cleanup-only findings (orphaned directories, closed issues with
local state), offer to clean them up in batch:

```
Found 2 orphaned directories and 1 stale label.
Clean up orphaned directories? (This removes .orchestrator/plans/<slug>/ for completed plans.)
```

Do not clean up automatically — ask first, since local state may
contain useful done-files or logs the user wants to review.

For stale labels, offer to update them via `gh issue edit`.

## 7. Summary

Print a final status line:

```
Sync complete. 3 open plans, 1 drift issue flagged (1 orphaned directory).
```

Or if clean:

```
Sync complete. 2 open plans, no drift detected.
```
