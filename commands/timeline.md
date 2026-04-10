# Update Timeline

@description View or update project timeline via the provider abstraction (Issues and Project board).
@arguments $UPDATE: Status changes to apply (e.g. "mark Conductor as done, MCP Server is active"), or "status" to show current state

View or update the project timeline based on the user's instructions in $UPDATE.

## Provider setup

Source the provider shim before any API calls:

```bash
source scripts/providers/provider.sh
```

This loads the active provider configured in `dega-core.yaml` (`provider:` field).
All issue, milestone, and project board operations use `provider_*` functions —
never call provider CLIs (e.g., `gh`) directly.

## Source of truth

Read `timeline` config from `dega-core.yaml` in the project root:

```yaml
timeline:
  repo: DEGAorg/claude-code-config   # repo (resolved via provider)
  project_number: 8                  # project board number
```

If `dega-core.yaml` is missing or has no `timeline` block, abort with an
error telling the user to add the config.

## Steps

### 1. Read config

Parse `dega-core.yaml` from the project root. Extract `timeline.repo` and
`timeline.project_number`.

### 2. Fetch current timeline

Retrieve milestones and their issues using provider functions:

```bash
# List all milestones with open/closed counts
provider_milestone_list --repo "${REPO}" --state all

# List all issues with their labels, milestone, and assignees
provider_issue_list --repo "${REPO}" --state all --limit 200
```

Retrieve project board item statuses:

```bash
# Get the org/owner from the repo
ORG="${REPO%%/*}"

# Query project items with Status field values
provider_project_items_list --project "${PROJECT_NUMBER}" --owner "${ORG}" \
  --limit 200
```

### 3. Display current status (if $UPDATE is "status")

If the user asked for status, display a summary table:

| Milestone | Done | Active | Todo | Target |
|-----------|------|--------|------|--------|

For each milestone, count issues by their project board Status field
(Done / In Progress / Todo). Show the milestone due date as Target.

Then list any issues with `risk:medium` or `risk:high` labels as flagged
items.

Stop here if $UPDATE is "status" — do not modify anything.

### 4. Apply status updates

Parse $UPDATE and identify which issues to update. Match items by
name (fuzzy — "Conductor" matches "TOAD TUI + Conductor", etc.).

Valid status transitions map to the project board Status field:

| User says | Project Status field |
|-----------|---------------------|
| `done` | Done |
| `active` | In Progress |
| `pending` | Todo |

For each matched issue:

#### a. Update project board Status field

```bash
# Get the item ID and Status field ID from the project items list
ITEMS_JSON=$(provider_project_items_list --project "${PROJECT_NUMBER}" \
  --owner "${ORG}" --limit 200)
ITEM_ID=$(echo "${ITEMS_JSON}" | jq -r \
  '.items[] | select(.content.number == ISSUE_NUM) | .id')

# Field and option IDs still require project field metadata (provider-
# specific — the provider_project_field_edit function handles the write)
provider_project_field_edit \
  --project-id "${PROJECT_ID}" \
  --item-id "${ITEM_ID}" \
  --field-id "${STATUS_FIELD_ID}" \
  --value "${OPTION_ID}"
```

#### b. Close or reopen the issue if needed

```bash
# If status is "done", close the issue
provider_issue_close --issue "${ISSUE_NUM}" --repo "${REPO}"

# If status is "active" or "pending" and issue is closed, reopen it
# (use provider_issue_edit to add/remove labels or change state as needed)
provider_issue_edit --issue "${ISSUE_NUM}" --repo "${REPO}"
```

### 5. Confirm

Report what changed:
- Which issues were updated and to what status (include issue numbers)
- Current summary per milestone: N done, N active, N todo
