# Apply Core

@description Deprecated pointer. Install/update DEGA Core by fetching and following `INSTALL.md` from `DEGAorg/claude-code-config@main`.

This command is a thin pointer. The authoritative install procedure lives in
[`INSTALL.md`](https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/INSTALL.md).

Re-running `INSTALL.md` against an existing install is also the supported
**update** path — it is idempotent. For the NL-triggered update flow
(`"update dega core"`, `/core-update`), see [`commands/core-update.md`](core-update.md).

## Steps

1. Fetch the latest `INSTALL.md`:

   ```
   https://raw.githubusercontent.com/DEGAorg/claude-code-config/main/INSTALL.md
   ```

2. Follow every step in that file, in order. It covers prerequisites,
   component selection, `~/.degacore/` layout, per-agent config generation,
   and post-install verification.

3. Do not reimplement install logic here — if something is missing or
   unclear, fix `INSTALL.md` upstream rather than expanding this pointer.
