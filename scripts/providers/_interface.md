# Provider Interface Contract

Each provider implements this interface as shell functions in a single
file (e.g., `github.sh`, `gitlab.sh`). The shim `provider.sh` sources
the active provider based on `dega-core.yaml`'s `provider:` field.

Callers source `provider.sh` — never a specific provider directly.

## Conventions

- **Exit codes:** 0 = success, 1 = error, 2 = auth failure.
- **Output:** Functions print results to stdout. Diagnostics go to stderr.
- **Errors:** Print `error: <message>` to stderr and return non-zero.
  Include context (operation, input) so callers can surface actionable
  messages.
- **No globals:** Functions receive all inputs as arguments. Provider-
  specific config (repo, project number) is read from `dega-core.yaml`
  by the provider, not passed by callers.
- **Idempotent where possible:** Label removal on a missing label, or
  closing an already-closed issue, should succeed silently.
- **JSON output:** Functions returning structured data use JSON (one
  object per line, or a JSON array). Callers parse with `jq`.

## Required functions

### Authentication

#### `provider_ensure_cli`

Ensure the provider's CLI tool is installed. Install via Homebrew if
available; otherwise print platform-specific install instructions and
return 1.

```
Arguments: (none)
Stdout:    (none)
Exit:      0 if CLI is available, 1 if install failed
```

#### `provider_auth_check`

Verify the current user is authenticated with the provider.

```
Arguments: (none)
Stdout:    (none)
Exit:      0 if authenticated, 2 if not
Stderr:    On failure, print instructions to authenticate
```

### Repository resolution

#### `provider_repo_resolve [--repo OWNER/REPO]`

Resolve the target repository using the standard fallback chain:
1. Explicit `--repo` value (if provided)
2. `dega-core.yaml` config (provider-specific block, e.g., `github.repo`)
3. Auto-detection from git remote

```
Arguments: [--repo OWNER/REPO]   optional explicit override
Stdout:    OWNER/REPO
Exit:      0 on success, 1 if resolution fails
```

### Issues

#### `provider_issue_create`

Create an issue and return its identifier.

```
Arguments:
  --title TITLE          required
  --body BODY            required (mutually exclusive with --body-file)
  --body-file PATH       required (mutually exclusive with --body;
                         use "-" for stdin)
  --repo OWNER/REPO      optional (default: provider_repo_resolve)
  --label LABEL          optional, repeatable

Stdout:    Issue number (integer)
Exit:      0 on success, 1 on failure
```

#### `provider_issue_view`

Fetch issue metadata as JSON.

```
Arguments:
  --issue NUMBER         required
  --repo OWNER/REPO      optional
  --fields FIELD,...     optional, comma-separated list of fields to return
                         Supported fields: body, state, labels, title,
                         assignees, milestone

Stdout:    JSON object with requested fields (all fields if --fields omitted)
           Example: {"body": "...", "state": "OPEN", "labels": ["plan:active"]}
Exit:      0 on success, 1 on failure
```

#### `provider_issue_edit`

Update an issue's body, labels, or other mutable fields.

```
Arguments:
  --issue NUMBER         required
  --repo OWNER/REPO      optional
  --body BODY            optional — replace the issue body
  --add-label LABEL      optional, repeatable
  --remove-label LABEL   optional, repeatable

Stdout:    (none)
Exit:      0 on success, 1 on failure
```

#### `provider_issue_comment`

Post a comment on an issue.

```
Arguments:
  --issue NUMBER         required
  --repo OWNER/REPO      optional
  --body BODY            required

Stdout:    (none)
Exit:      0 on success, 1 on failure
```

#### `provider_issue_close`

Close an issue. Idempotent — closing an already-closed issue succeeds.

```
Arguments:
  --issue NUMBER         required
  --repo OWNER/REPO      optional

Stdout:    (none)
Exit:      0 on success, 1 on failure
```

#### `provider_issue_list`

List issues matching filters, returned as a JSON array.

```
Arguments:
  --repo OWNER/REPO      optional
  --state STATE          optional (open, closed, all; default: open)
  --label LABEL          optional, repeatable — filter by label
  --limit N              optional (default: 100)

Stdout:    JSON array of objects, each with at minimum:
           {number, title, state, labels, milestone, assignees}
Exit:      0 on success, 1 on failure
```

### Pull requests

#### `provider_pr_create`

Create a pull request and return its URL.

```
Arguments:
  --title TITLE          required
  --body BODY            required
  --base BRANCH          required — target branch
  --head BRANCH          required — source branch
  --repo OWNER/REPO      optional

Stdout:    PR URL (e.g., https://github.com/org/repo/pull/42)
Exit:      0 on success, 1 on failure
```

### Push and PR

For lifecycle hooks and the orchestrator engine, prefer
`scripts/gh-push-and-pr.sh` over calling `provider_pr_create` directly.
The wrapper owns the full push → propagation-poll → diff-sanity →
PR-create → issue-comment flow and is race-aware against GitHub's
read-replica propagation lag.

It still calls `provider_pr_create` under the hood, so the provider
abstraction is preserved — callers just get retries, polling, and an
idempotent issue comment for free.

#### Flags

```
--worktree <path>             required — worktree to push from
--branch <branch>             required — head branch
--base <branch>               required — base branch
--title <string>              required — PR title
--body-file <path>            required — PR body file
--issue <N>                   optional — post the PR URL as a comment
--plan-slug <slug>            optional — key for posted.json idempotency
                              (defaults to basename of --worktree)
--propagation-timeout <s>     optional — default 30
--create-retries <n>          optional — default 3
--create-backoff <s>          optional — default 3 (multiplied by attempt)
```

Stdout is the PR URL on success. Stderr carries `<CLASS>: <details>` on
failure.

#### Exit codes

| Code | Class                  | Meaning                                              |
|------|------------------------|------------------------------------------------------|
| 0    | `OK`                   | PR created (and comment posted, if `--issue` given)  |
| 1    | `PROPAGATION_TIMEOUT`  | Branch never appeared on the remote within timeout   |
| 2    | `NO_COMMITS`           | Branch has no commits ahead of base                  |
| 3    | `AUTH`                 | Authentication or permissions failure                |
| 4    | `VALIDATION`           | Bad arguments or missing input                       |
| 5    | `OTHER`                | Unclassified failure                                 |

The PR-create step retries the known-transient failure class
(`Head sha can't be blank`, `Base sha can't be blank`, `No commits
between`, `Head ref must be a branch`, `Base ref must be a branch`) up
to `--create-retries` times with `attempt * --create-backoff` second
sleeps. Push itself is not retried.

The `--issue` comment is idempotent: the script reads and writes
`${ORCH_STATE_DIR:-.orchestrator}/posted.json` keyed by
`<plan-slug>:pr-link`, so re-running the script for the same plan does
not double-post.

### Labels

#### `provider_labels_get`

Get all labels currently on an issue, as a comma-separated string.

```
Arguments:
  --issue NUMBER         required
  --repo OWNER/REPO      optional

Stdout:    Comma-separated label names (e.g., "plan:active,bug")
           Empty string if no labels.
Exit:      0 on success, 1 on failure
```

#### `provider_labels_set`

Replace plan-lifecycle labels on an issue. Removes any existing labels
from the `plan:*` family, then adds the specified label.

This is a convenience function for the common pattern of transitioning
between plan states. For arbitrary label edits, use `provider_issue_edit`.

```
Arguments:
  --issue NUMBER         required
  --repo OWNER/REPO      optional
  --label LABEL          required — the label to apply
  --family PREFIX        optional (default: "plan:")
                         Prefix identifying labels to remove before applying

Stdout:    (none)
Exit:      0 on success, 1 on failure
```

### Milestones

#### `provider_milestone_list`

List all milestones for a repository.

```
Arguments:
  --repo OWNER/REPO      optional
  --state STATE          optional (open, closed, all; default: all)

Stdout:    JSON array of objects:
           {number, title, description, due_on, open_issues, closed_issues}
Exit:      0 on success, 1 on failure
```

### Project boards

#### `provider_project_items_list`

List items on a project board.

```
Arguments:
  --project NUMBER       required — project board number
  --owner OWNER          required — organization or user that owns the project
  --limit N              optional (default: 200)

Stdout:    JSON (format matches provider's native output)
Exit:      0 on success, 1 on failure
```

#### `provider_project_field_edit`

Set a field value on a project board item.

```
Arguments:
  --project-id ID        required — project node ID
  --item-id ID           required — item node ID
  --field-id ID          required — field node ID
  --value VALUE          required — option ID for single-select fields,
                         or text value for text fields

Stdout:    (none)
Exit:      0 on success, 1 on failure
```

### Configuration

#### `provider_config_value KEY`

Read a provider-specific configuration value from `dega-core.yaml`.
The provider decides which YAML block to read (e.g., GitHub reads from
the `github:` block).

```
Arguments: KEY           the config key name
Stdout:    Value as a string, or empty if unset
Exit:      0 always
```

#### `provider_config_bool KEY`

Check if a provider-specific config key is boolean true.

```
Arguments: KEY           the config key name
Exit:      0 if true, 1 if false or unset
```

## Provider-specific config in `dega-core.yaml`

Each provider reads its own block. The `provider:` key at the root level
selects which provider to load.

```yaml
provider: github

github:
  repo: DEGAorg/claude-code-config
  sync: true
  labels: true
  comments: true
  close_on_ship: true
```

A different provider (e.g., GitLab) would use its own block:

```yaml
provider: gitlab

gitlab:
  repo: myorg/myproject
  url: https://gitlab.example.com
```

## Implementing a new provider

1. Create `scripts/providers/<name>.sh`
2. Implement every function listed above
3. Add the provider's config block to `dega-core.yaml`
4. Set `provider: <name>` in `dega-core.yaml`
5. Run the full test suite to verify

No changes to callers should be needed — the shim dispatches
automatically based on the `provider:` config value.
