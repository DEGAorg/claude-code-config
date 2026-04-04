# Update Timeline

@description View or update project timeline via GitHub Issues and Project board.
@arguments $UPDATE: Status changes to apply (e.g. "mark Conductor as done, MCP Server is active"), or "status" to show current state

View or update the project timeline based on the user's instructions in $UPDATE.

## Source of truth

Read `timeline` config from `dega-core.yaml` in the project root:

```yaml
timeline:
  repo: DEGAorg/claude-code-config   # GitHub repo
  project_number: 8                  # GitHub Project board number
```

If `dega-core.yaml` is missing or has no `timeline` block, abort with an
error telling the user to add the config.

## Steps

### 1. Read config

Parse `dega-core.yaml` from the project root. Extract `timeline.repo` and
`timeline.project_number`.

### 2. Fetch current timeline

Retrieve milestones and their issues using `gh`:

```bash
# List all milestones with open/closed counts
gh api "repos/${REPO}/milestones?state=all&per_page=100" \
  --jq '.[] | {number, title, description, due_on, open_issues, closed_issues}'

# List all open issues with their labels, milestone, and assignees
gh issue list --repo "${REPO}" --state all --limit 200 \
  --json number,title,state,labels,milestone,assignees
```

Retrieve project board item statuses:

```bash
# Get the GitHub org from the repo (owner)
ORG="${REPO%%/*}"

# Query project items with Status field values
gh project item-list "${PROJECT_NUMBER}" --owner "${ORG}" --format json \
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
# Get the item ID and Status field ID from the project
ITEM_ID=$(gh project item-list "${PROJECT_NUMBER}" --owner "${ORG}" \
  --format json | jq -r '.items[] | select(.content.number == ISSUE_NUM) | .id')

STATUS_FIELD_ID=$(gh project field-list "${PROJECT_NUMBER}" --owner "${ORG}" \
  --format json | jq -r '.fields[] | select(.name == "Status") | .id')

# Get the option ID for the target status value
OPTION_ID=$(gh project field-list "${PROJECT_NUMBER}" --owner "${ORG}" \
  --format json | jq -r '.fields[] | select(.name == "Status") | .options[] | select(.name == "TARGET_STATUS") | .id')

gh project item-edit --project-id "${PROJECT_ID}" --id "${ITEM_ID}" \
  --field-id "${STATUS_FIELD_ID}" --single-select-option-id "${OPTION_ID}"
```

#### b. Close or reopen the issue if needed

```bash
# If status is "done", close the issue
gh issue close ISSUE_NUM --repo "${REPO}"

# If status is "active" or "pending" and issue is closed, reopen it
gh issue reopen ISSUE_NUM --repo "${REPO}"
```

### 5. Confirm

Report what changed:
- Which issues were updated and to what status (include issue numbers)
- Current summary per milestone: N done, N active, N todo
