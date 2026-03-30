# Human Tasks — Alberto

Things that require human action (auth, accounts, decisions) and cannot be done by Claude.

---

## Blocking (do these first)

### 1. Authenticate GitHub CLI
```bash
gh auth login
```
Choose GitHub.com, HTTPS, browser auth. Required for both Plan 1 (GitHub Issues) and Plan 2 (Conductor TUI).

**Verify:** `gh auth status` shows authenticated.

### 2. Fork Toad repo
```bash
gh repo fork batrachianai/toad --org DEGAorg --clone=false
```
Or fork via GitHub UI to DEGAorg. Decide on repo name:
- `canon-conductor` (recommended — describes what it becomes)
- `toad` (keep original name)
- Other?

**Decision needed:** repo name for the fork.

### 3. Clone the fork locally
Once forked and named:
```bash
cd ~/dega
gh repo clone DEGAorg/<repo-name>
cd <repo-name>
uv venv && uv pip install -e ".[dev]"
```
Verify it runs: `toad` or `python -m toad`.

### 4. Create GitHub labels for plan lifecycle
On the `claude-code-config` repo (or whichever repo uses GitHub Issues as plans):
```bash
gh label create "plan:draft" --color "C5DEF5" --description "Plan created, not executing"
gh label create "plan:active" --color "0E8A16" --description "Orchestrator running"
gh label create "plan:review" --color "FBCA04" --description "Review phase"
gh label create "plan:completed" --color "6F42C1" --description "Shipped"
gh label create "plan:failed" --color "D93F0B" --description "Needs human intervention"
```

---

## Non-blocking (can do after plans start)

### 5. Decide AGPL acknowledgment
The Toad fork is AGPL-3.0. Confirm this is acceptable for the conductor TUI.
Per the decision doc (`docs/decisions/20260320-tui-framework-selection.md`):
- Only the TUI app is AGPL
- MCP server, skills, agents stay Apache 2.0
- Arena, cloud exec, marketplace are proprietary and unaffected

### 6. Decide upstream tracking policy
Will we track Toad upstream (merge Will's updates) or diverge permanently?
- Track: get free improvements, but merge conflicts
- Diverge: full control, but maintain everything ourselves

### 7. Add `github:` block to dega-core.yaml
Once Plan 1 scripts are ready, add to any project that wants GitHub Issues as plans:
```yaml
github:
  sync: true
  labels: true
  comments: true
  close_on_ship: true
```
