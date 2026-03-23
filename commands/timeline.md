# Update Timeline

@description Update project timeline statuses in the shared repo file.
@arguments $UPDATE: Status changes to apply (e.g. "mark Conductor as done, MCP Server is active")

Update the project timeline based on the user's instructions in $UPDATE.

## Source of truth

Read `timeline` config from `dega-core.yaml` in the project root:

```yaml
timeline:
  repo: DEGAorg/claude-code-config   # GitHub repo
  branch: develop                     # branch where timeline lives
  path: data/timeline.json            # file path in repo
```

If `dega-core.yaml` is missing or has no `timeline` block, abort with an
error telling the user to add the config.

## Steps

### 1. Read config

Parse `dega-core.yaml` from the project root. Extract `timeline.repo`,
`timeline.branch`, and `timeline.path`.

### 2. Fetch current timeline

```bash
gh api "repos/${REPO}/contents/${PATH}?ref=${BRANCH}" --jq '.content' | base64 -d > /tmp/timeline.json
```

Read the JSON to understand the current state.

### 3. Apply status updates

Parse $UPDATE and modify the `status` field on matching items in both
`components` and `ganttBars` arrays. Valid statuses:

| Status | Meaning |
|--------|---------|
| `done` | Completed |
| `active` | Currently in progress |
| `pending` | Not started |

Match items by name/label (fuzzy — "Conductor" matches "Conductor + TUI",
"TOAD TUI + Conductor", etc.). Update both `components` (by `name`) and
`ganttBars` (by `label`) when they refer to the same item.

### 4. Update metadata

Set `meta.generated` to today's date (YYYY-MM-DD format).

### 5. Push update

```bash
SHA=$(gh api "repos/${REPO}/contents/${PATH}?ref=${BRANCH}" --jq '.sha')

gh api "repos/${REPO}/contents/${PATH}" \
  -X PUT \
  -f message="timeline: update statuses" \
  -f branch="${BRANCH}" \
  -f sha="$SHA" \
  -f content="$(base64 < /tmp/timeline.json)"
```

### 6. Confirm

Report what changed:
- Which items were updated and to what status
- Current summary: N done, N active, N pending
