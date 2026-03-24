# Plan: Fix shebang inconsistency across scripts and hooks

**Status:** In progress
**Created:** 2026-03-24

## Requirements

- All shell scripts use `#!/usr/bin/env bash` instead of `#!/bin/bash`
- Matches the project standard from `rules/bash.md`
- No functional changes — pure mechanical fix

## Approach

6 files use `#!/bin/bash`. Replace with `#!/usr/bin/env bash` in each. The `env` form is portable across macOS (where bash is at `/opt/homebrew/bin/bash` on Apple Silicon) and Linux.

## Files to touch

| File | Change |
|------|--------|
| `hooks/enforce-package-manager.sh` | Fix shebang |
| `hooks/play-sound.sh` | Fix shebang |
| `hooks/log-gam.sh` | Fix shebang |
| `scripts/statusline.sh` | Fix shebang |
| `scripts/orch-display.sh` | Fix shebang |
| `scripts/dev-test/test-sound.sh` | Fix shebang |

## Risks and open questions

- None. Mechanical replacement with no behavioral change.

## Questions for reviewer

No blocking questions.

## Progress log

- [ ] Replace `#!/bin/bash` with `#!/usr/bin/env bash` in all 6 files and verify with `rg '#!/bin/bash' scripts/ hooks/`

## Decision log

| Decision | Alternatives considered | Rationale |
|----------|------------------------|-----------|
| `#!/usr/bin/env bash` | `#!/bin/bash`, `#!/usr/bin/bash` | Portable — works on macOS (Homebrew bash), NixOS, and standard Linux |

## Completion criteria

- [ ] `rg '#!/bin/bash' scripts/ hooks/` returns no matches
- [ ] `shellcheck -e SC1091 -S warning hooks/enforce-package-manager.sh hooks/play-sound.sh hooks/log-gam.sh scripts/statusline.sh scripts/orch-display.sh` passes
