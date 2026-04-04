# Timeline API Guide — Canon TUI Integration

How to read and update project timeline data from the GitHub Issues API
and Projects API instead of the legacy `timeline.json` file.

## Source of truth

All timeline data lives on **DEGAorg/claude-code-config**:

| Resource | Identifier |
|----------|-----------|
| Repository | `DEGAorg/claude-code-config` |
| Project board | #8 ("Canon Hackathon") |
| Config | `dega-core.yaml` → `timeline` block |

```yaml
# dega-core.yaml
timeline:
  repo: DEGAorg/claude-code-config
  project_number: 8
```

## Data model

### Milestones

Each major feature or module maps to a GitHub milestone. Milestones group
related issues and carry a due date.

| Milestone | Purpose |
|-----------|---------|
| Canon TUI | Toad fork with agent control, split view |
| pmxt POC | Polymarket exchange test — gate before CLI |
| RPA Tool | Playwright scraper for DoraHacks outreach |
| Canon CLI (init + start) | canon init and canon start commands |
| Canon CLI (register + help + wallet) | Remaining CLI commands (needs Arena) |
| Strategies Research | Sampson's 18 strategy types review |
| Templates (TS) | TypeScript base template codebase |
| Templates (Python) | Python base template codebase |
| Strategy Implementation | Strategy-specific configs on TS/Python base |
| Arena MVP | Next.js leaderboard, registration, portfolio |
| Demo Video | YouTube demo recorded Mar 30 |
| Update RPA Session | RPA session update |
| Integration Test | Integration + smoke tests |
| Testing Phase | Heavy testing + bug fixes |
| DoraHacks + DMs | Listing + DM outreach campaigns |
| Content Tracking | Workshop content due Apr 5-11 |
| Workshops | 5 sessions: Apr 8, 10, 15, 17, 29 |
| Hackathon | 3-week NBA Playoffs competition |
| Finale | Judging + Winners livestream |

### Labels

Issues carry labels for filtering and display:

| Category | Labels |
|----------|--------|
| Priority | `p1-must-ship`, `p2-should-ship`, `p3-nice`, `p4-cut` |
| Risk | `risk:low`, `risk:medium`, `risk:high` |
| Workflow | `gate` (blocking checkpoint), `orch` (orchestrator-managed) |

### Project board custom fields

Project #8 has four custom fields on every item:

| Field | Type | Values |
|-------|------|--------|
| Status | Single select | `Todo`, `In Progress`, `Done` |
| Effort | Number | Days of work |
| Start Date | Date | ISO 8601 (YYYY-MM-DD) |
| Target Date | Date | ISO 8601 (YYYY-MM-DD) |

## Reading timeline data

All commands below use these variables:

```bash
REPO="DEGAorg/claude-code-config"
ORG="DEGAorg"
PROJECT_NUMBER=8
```

### List milestones

```bash
gh api "repos/${REPO}/milestones?state=all&per_page=100" \
  --jq '.[] | {number, title, description, due_on, open_issues, closed_issues}'
```

Returns per milestone:
- `number` — milestone ID (use for filtering issues)
- `title` — display name
- `due_on` — target date (ISO 8601) or `null`
- `open_issues` / `closed_issues` — counts

### List all issues

```bash
gh issue list --repo "${REPO}" --state all --limit 200 \
  --json number,title,state,labels,milestone,assignees
```

Returns per issue:
- `number` — issue ID
- `title` — display name
- `state` — `OPEN` or `CLOSED`
- `labels` — array of `{name}` objects
- `milestone` — `{title, number}` or `null`
- `assignees` — array of `{login}` objects

### Filter issues by label

```bash
# All gate issues
gh issue list --repo "${REPO}" --label "gate" --state all --limit 200 \
  --json number,title,state

# High-risk items
gh issue list --repo "${REPO}" --label "risk:high" --state all --limit 200 \
  --json number,title,state,milestone

# Must-ship items
gh issue list --repo "${REPO}" --label "p1-must-ship" --state all --limit 200 \
  --json number,title,state,milestone
```

### Filter issues by milestone

```bash
# Issues in a specific milestone
gh issue list --repo "${REPO}" --milestone "Arena MVP" --state all \
  --limit 200 --json number,title,state,labels
```

### Get project board items with custom fields

```bash
gh project item-list "${PROJECT_NUMBER}" --owner "${ORG}" \
  --format json --limit 200
```

Returns an `items` array. Each item includes:
- `id` — project item ID (needed for field updates)
- `title` — issue title
- `content.number` — linked issue number
- Field values for Status, Effort, Start Date, Target Date

### Get project field definitions

```bash
gh project field-list "${PROJECT_NUMBER}" --owner "${ORG}" --format json
```

Returns field metadata including IDs and, for single-select fields like
Status, the available option IDs. Cache these — they rarely change.

### Get a single issue

```bash
gh issue view 84 --repo "${REPO}" \
  --json number,title,body,labels,milestone,state,assignees
```

## Updating timeline data

### Change project board Status

Updating Status requires the item ID, field ID, and option ID:

```bash
# 1. Get the project item ID for a given issue number
ITEM_ID=$(gh project item-list "${PROJECT_NUMBER}" --owner "${ORG}" \
  --format json | jq -r ".items[] | select(.content.number == ${ISSUE_NUM}) | .id")

# 2. Get the Status field ID
STATUS_FIELD_ID=$(gh project field-list "${PROJECT_NUMBER}" --owner "${ORG}" \
  --format json | jq -r '.fields[] | select(.name == "Status") | .id')

# 3. Get the option ID for the target status
TARGET="In Progress"  # or "Todo" or "Done"
OPTION_ID=$(gh project field-list "${PROJECT_NUMBER}" --owner "${ORG}" \
  --format json | jq -r ".fields[] | select(.name == \"Status\") | .options[] | select(.name == \"${TARGET}\") | .id")

# 4. Update the field
gh project item-edit --project-id "${PROJECT_ID}" --id "${ITEM_ID}" \
  --field-id "${STATUS_FIELD_ID}" --single-select-option-id "${OPTION_ID}"
```

### Close or reopen an issue

```bash
# Mark done — close the issue
gh issue close "${ISSUE_NUM}" --repo "${REPO}"

# Mark active or pending — reopen if closed
gh issue reopen "${ISSUE_NUM}" --repo "${REPO}"
```

### Update date fields

```bash
# Get the field ID
FIELD_ID=$(gh project field-list "${PROJECT_NUMBER}" --owner "${ORG}" \
  --format json | jq -r '.fields[] | select(.name == "Start Date") | .id')

# Set the date
gh project item-edit --project-id "${PROJECT_ID}" --id "${ITEM_ID}" \
  --field-id "${FIELD_ID}" --date "2026-04-15"
```

### Update Effort field

```bash
FIELD_ID=$(gh project field-list "${PROJECT_NUMBER}" --owner "${ORG}" \
  --format json | jq -r '.fields[] | select(.name == "Effort") | .id')

gh project item-edit --project-id "${PROJECT_ID}" --id "${ITEM_ID}" \
  --field-id "${FIELD_ID}" --number 5
```

### Edit issue metadata

```bash
gh issue edit "${ISSUE_NUM}" --repo "${REPO}" \
  --add-label "risk:high" \
  --remove-label "risk:low" \
  --milestone "Arena MVP"
```

## Building a timeline view

To render a Gantt-style or table view, combine milestones, issues, and
project board data:

1. **Fetch milestones** — provides grouping and due dates
2. **Fetch issues** — provides titles, labels, state, milestone assignment
3. **Fetch project items** — provides Status, Effort, Start Date, Target Date

Join issues to project items on `content.number == issue.number`. Group
by milestone. Sort within each group by Start Date.

### Status mapping

| Project Status | Display | Issue state |
|---------------|---------|-------------|
| Todo | Pending | OPEN |
| In Progress | Active | OPEN |
| Done | Complete | CLOSED |

### Recommended display columns

| Column | Source |
|--------|--------|
| Title | Issue title |
| Milestone | Issue milestone |
| Status | Project board Status field |
| Priority | Issue label (`p1`–`p4`) |
| Risk | Issue label (`risk:*`) |
| Effort | Project board Effort field (days) |
| Start | Project board Start Date |
| Target | Project board Target Date |
| Gate | Issue has `gate` label |

## Authentication

All `gh` commands require an authenticated GitHub CLI session:

```bash
gh auth status  # verify authentication
gh auth login   # authenticate if needed
```

The TUI should check `gh auth status` on startup and surface a clear
error if the user is not authenticated.
