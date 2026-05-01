# Orch: Extract `push-and-pr` into a dedicated script

## Problem

`orch-engine.sh` runs the SHIP sequence inline. Step 8/9 pushes the worktree
branch and immediately calls `provider_pr_create`. GitHub's PR API runs
against a replica that may not yet have indexed the freshly-pushed branch,
so the create call fails with errors like:

```
GraphQL: Head sha can't be blank, Base sha can't be blank,
No commits between <base> and <branch>,
Head ref must be a branch, Base ref must be a branch
(createPullRequest)
```

The push succeeded; GitHub just didn't see the branch yet. orch-engine
treats this as non-fatal and continues — worktree is cleaned up, branch
stays pushed, no PR is opened, user is left with an orphan branch.

Observed in real run: plan `20260427-plan-execution-bootstrap` (issue
[DEGAorg/canon-tui#37](https://github.com/DEGAorg/canon-tui/issues/37)),
log line 148-149 of
`.orchestrator/plans/20260427-plan-execution-bootstrap/logs/engine.log`.
Manual `gh pr create` ~60s later succeeded on first try (PR #38) — pure
propagation race.

## Solution

Extract the push-then-PR flow into a dedicated, self-contained script.
orch-engine calls it once; the script owns retry, validation, timing,
and structured exit codes.

### Location

`~/.claude/scripts/gh-push-and-pr.sh`

(Or `~/.claude/scripts/providers/push-and-pr.sh` if it should sit beside
`provider.sh` to allow a non-GitHub backend later. The interface should
be backend-agnostic; the GitHub specifics live behind `provider_pr_create`
which already exists in `providers/github.sh`.)

### Interface

```bash
gh-push-and-pr.sh \
  --worktree <path> \
  --branch <branch> \
  --base <branch> \
  --title <string> \
  --body-file <path> \
  --issue <N>                  # optional — used for "Closes #N" + PR-link comment
  --propagation-timeout 30     # default 30s, max wait for remote ref to match local SHA
  --create-retries 3           # default 3, retries on the known transient PR-create class
  --create-backoff 3           # default 3s base, multiplied per attempt
```

### Steps

1. **Push**
   - `git -C <worktree> push -u origin <branch>`
   - Fail fast on real push errors (auth, ref already exists with diverged
     SHA, network). Don't retry the push itself — it's deterministic.

2. **Propagation poll**
   - Compute local SHA: `git -C <worktree> rev-parse <branch>`.
   - Loop: `gh api repos/<repo>/branches/<branch> --jq '.commit.sha'`
     until it equals the local SHA, or `--propagation-timeout` elapses.
   - Backoff: 1s, 2s, 3s, ... capped at 5s per attempt.
   - Distinguish "branch not seen yet" (404 → retry) from "branch missing
     after push success" (consistent failure → exit `PROPAGATION_TIMEOUT`).

3. **Diff sanity**
   - `gh api repos/<repo>/compare/<base>...<branch> --jq '.ahead_by'`
   - If `0`, exit `NO_COMMITS` immediately. Catches the empty-PR case
     before it surfaces as a GraphQL error.

4. **PR create**
   - Call `provider_pr_create --title --body --base --head`.
   - On failure, classify stderr:
     - Transient (`Head sha can't be blank`, `Base sha can't be blank`,
       `No commits between`, `Head ref must be a branch`, `Base ref must be a branch`)
       → retry up to `--create-retries`, sleeping `attempt * --create-backoff` seconds.
     - Auth / permissions / validation → exit `AUTH` or `VALIDATION`, no retry.
     - Other → exit `OTHER` with full stderr.

5. **Side effects** (only after PR create returns 0)
   - If `--issue` is set, post `PR created: <url>` comment via
     `provider_issue_comment`.
   - Idempotency: check `posted.json` (same pattern lifecycle hooks
     already use) before posting to avoid duplicates on resume.

6. **Output**
   - Stdout: PR URL on success.
   - Stderr: structured error on failure: `<CLASS>: <details>`.
   - Exit codes: `0` ok, `1` `PROPAGATION_TIMEOUT`, `2` `NO_COMMITS`,
     `3` `AUTH`, `4` `VALIDATION`, `5` `OTHER`.

### Caller change in `orch-engine.sh`

Replace the inline block at SHIP 8/9 (~L850-895) with:

```bash
if PR_URL=$(gh-push-and-pr.sh \
    --worktree "${WORKTREE_DIR_PUSH}" \
    --branch "${ORCH_BRANCH}" \
    --base "${PR_TARGET}" \
    --title "${PR_TITLE}" \
    --body-file "${PR_BODY_FILE}" \
    --issue "${ISSUE_NUMBER:-}" 2>"${PR_ERR_FILE}"); then
  echo "orch-engine: PR created: ${PR_URL}"
else
  rc=$?
  case "${rc}" in
    1) echo "orch-engine: WARN — PR creation timed out waiting for branch propagation" >&2 ;;
    2) echo "orch-engine: WARN — branch has no commits ahead of base; nothing to PR" >&2 ;;
    3) echo "orch-engine: ERROR — auth/permissions failure on PR create" >&2 ;;
    *) echo "orch-engine: WARN — PR creation failed (rc=${rc})" >&2 ;;
  esac
  cat "${PR_ERR_FILE}" >&2
fi
```

The caller decides whether to fail the SHIP or continue; the script's
exit code makes the failure class actionable.

## Why a dedicated script

- **Independently testable.** `bats` (or a Python pytest harness) can mock
  `gh` and `git` and exercise every retry path. Inline code in a 1000-line
  shell script can't realistically be tested.
- **Reusable.** Any future lifecycle hook that needs to push-and-PR
  (revise → resubmission, retry-failed-plan, manual replays) gets the
  same race-handling for free.
- **Tighter blast radius.** When the race-handling logic changes, the
  diff is in one ~80-line file, not buried in orch-engine.
- **Better error reporting.** The structured exit codes let downstream
  tooling (and humans) tell "GitHub was slow, retry the SHIP" apart from
  "your auth is broken, fix that first."

## Acceptance

- [ ] `gh-push-and-pr.sh` exists and passes `shellcheck`/`shfmt`.
- [ ] `bats tests/orch/push-and-pr.bats` covers: success, push failure,
  propagation timeout, no-commits, transient PR-create retry that
  eventually succeeds, transient that exhausts retries, auth failure.
- [ ] `orch-engine.sh` SHIP 8/9 calls the new script; the inline `git push`
  + `provider_pr_create` block is removed.
- [ ] Replay of plan `20260427-plan-execution-bootstrap` (or any plan)
  creates a PR on first SHIP, no manual follow-up.
- [ ] Doc: update `~/.claude/scripts/providers/_interface.md` to describe
  the script as the recommended way to call `provider_pr_create` from
  lifecycle hooks (don't call it directly).

## References

- Inline implementation today: `~/.claude/scripts/orch-engine.sh` ~L850-895
- Existing primitive: `provider_pr_create` in `~/.claude/scripts/providers/github.sh` L456+
- Real-world failure: `DEGAorg/canon-tui` issue #37, manual PR #38
- Lifecycle hook pattern (idempotency via `posted.json`):
  `~/.claude/hooks/orch-lifecycle/01-gh-plan-sync.sh`
