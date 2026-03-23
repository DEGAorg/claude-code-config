# Update Timeline

@description Update project timeline statuses in the shared repo file.
@arguments $UPDATE: Status changes to apply (e.g. "mark Conductor as done, MCP Server is active")

Update the project timeline based on the user's instructions in $UPDATE.

## Source of truth

- **File**: `data/timeline.json` in `DEGAorg/claude-code-config` on `develop` branch
- **Raw URL**: `https://raw.githubusercontent.com/DEGAorg/claude-code-config/develop/data/timeline.json`

## Steps

### 1. Fetch current timeline

```bash
gh api repos/DEGAorg/claude-code-config/contents/data/timeline.json?ref=develop --jq '.content' | base64 -d > /tmp/timeline.json
```

Read the JSON to understand the current state.

### 2. Apply status updates

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

### 3. Update metadata

Set `meta.generated` to today's date (YYYY-MM-DD format).

### 4. Write and push

If you are in the claude-code-config repo:

```bash
cp /tmp/timeline.json data/timeline.json
git add data/timeline.json
git commit -m "timeline: update statuses"
git push origin develop
```

If you are in a different repo, use the GitHub API:

```bash
# Get current SHA for the file
SHA=$(gh api repos/DEGAorg/claude-code-config/contents/data/timeline.json?ref=develop --jq '.sha')

# Push updated content
gh api repos/DEGAorg/claude-code-config/contents/data/timeline.json \
  -X PUT \
  -f message="timeline: update statuses" \
  -f branch=develop \
  -f sha="$SHA" \
  -f content="$(base64 < /tmp/timeline.json)"
```

### 5. Confirm

Report what changed:
- Which items were updated and to what status
- Current summary: N done, N active, N pending
