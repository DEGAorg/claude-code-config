---
glob: ".github/workflows/*.yml"
---

# GitHub Actions Standards

**Pin actions to SHA hashes** with version comments:
```yaml
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
  with:
    persist-credentials: false
```

**Scan before committing:** `zizmor .github/workflows/` — catches permission escalation, injection risks, and insecure patterns.

**Dependabot config:** 7-day cooldowns and grouped updates to reduce noise while staying current.

**Permissions:** Use least-privilege `permissions:` blocks on every job. Default to `contents: read`.
