# Fix orch_read_config() partial key matching

**Source:** Regression from PR #32 (`reduce-orchestrator-latency`, merged 2026-03-26)
**Hotfix:** `grep -m1 "^${key}:"` applied to `~/.claude/scripts/orch-state.sh` and repo copy

## Problem

`orch_read_config()` in `orch-state.sh:60` uses `grep "${key}:"` to read
YAML values. The grep is unanchored, so `poll_interval_seconds` also
matches `review_poll_interval_seconds` and `verify_poll_interval_seconds`.

The function returns a multiline string (`15\n10\n10`) instead of `15`.
`sleep` rejects this, the engine crashes after spawning workers, and all
subsequent items are orphaned forever. On restart the same crash repeats.

PR #32 introduced the collision by adding keys that share a suffix:

```yaml
poll_interval_seconds: 15          # ← target
review_poll_interval_seconds: 10   # ← also matched
verify_poll_interval_seconds: 10   # ← also matched
```

## Approach

1. Replace the naive grep with a proper anchored match that handles the
   flat YAML format used by `dega-core.yaml`.
2. Add a regression test that catches key-prefix collisions.
3. Propagate the fix to `~/.claude/scripts/` via `/apply-core`.
4. Verify all consumers of `orch_read_config` work with the new keys.

The function only needs to handle flat `key: value` pairs (no nesting,
no quoted strings, no multi-line values beyond `|` blocks). A full YAML
parser (yq) would be ideal but adds a dependency — anchored grep with
`-m1` is sufficient for the current config format.

## Requirements

1. `orch_read_config "poll_interval_seconds"` returns `15`, not `15\n10\n10`
2. `orch_read_config "review_poll_interval_seconds"` returns `10`
3. `orch_read_config "verify_poll_interval_seconds"` returns `10`
4. Nested keys (e.g. `github.sync`) still work via the existing `gh_config_bool` path
5. No new dependencies (no yq requirement)

## Progress log

- [x] Fix `orch_read_config()` in `scripts/orch-state.sh`: anchor grep with `^` and limit to first match with `-m1`
- [x] Verify `orch-engine.sh`, `orch-review.sh`, `orch-verify.sh` all read correct poll intervals with new keys (deps: 1)
- [x] Add regression test: call `orch_read_config` for all three poll interval keys against a sample config with prefix collisions (deps: 1)
- [x] Run shellcheck on modified files (deps: 1, 2, 3)
- [x] Run `/apply-core` to propagate fix to `~/.claude/scripts/` (deps: 4)

## Completion criteria

- [ ] `orch_read_config "poll_interval_seconds"` returns exactly `15` (single value, no newlines)
- [ ] `orch_read_config "review_poll_interval_seconds"` returns exactly `10`
- [ ] `orch_read_config "verify_poll_interval_seconds"` returns exactly `10`
- [ ] Regression test exists and passes
- [ ] shellcheck clean on all modified files
