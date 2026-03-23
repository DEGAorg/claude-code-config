# Update Timeline

@description Update project timeline statuses in the shared gist.
@arguments $UPDATE: Status changes to apply (e.g. "mark Conductor as done, MCP Server is active")

Update the project timeline gist based on the user's instructions in $UPDATE.

## Gist

- **Gist ID**: `a11220a561b98d07b4538049c3b13770`
- **Raw URL**: `https://gist.githubusercontent.com/CerratoA/a11220a561b98d07b4538049c3b13770/raw/timeline.json`

## Steps

### 1. Fetch current timeline

```bash
gh gist view a11220a561b98d07b4538049c3b13770 -f timeline.json > /tmp/timeline.json
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

### 4. Write the updated JSON

Write the modified JSON back to `/tmp/timeline.json` (pretty-printed,
2-space indent).

### 5. Push to gist

```bash
gh gist edit a11220a561b98d07b4538049c3b13770 -f timeline.json /tmp/timeline.json
```

### 6. Confirm

Report what changed:
- Which items were updated and to what status
- Current summary: N done, N active, N pending
