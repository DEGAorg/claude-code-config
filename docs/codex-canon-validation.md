# Canon entry points in Codex

Scope: repair discovery and installation of `canon-start` and `canon-init`.
The backing requirement is the host-agnostic framework in Canon Docs,
`specs/SAS_Agent_Framework.md`, Design Principles §2 and multi-host acceptance
criteria. The existing command procedures define the workflow; this fix adds
Codex host adapters rather than a second strategy implementation.

## Implementation

- Native skills under `skills/codex/` describe the two entry points.
- `scripts/install-canon-codex.sh SOURCE_ROOT [SKILLS_DIR]` bundles the shared
  command references and installs the skills. SOURCE_ROOT is a checkout or the
  installed `~/.degacore/config` cache.
- Both skills and commands must exist before installation starts. Existing
  installer-managed files can be updated only when their recorded checksums still
  match. User-owned and edited skills produce errors before any skill is written.
- Canon Bootstrap fetches both commands even when Commands was not selected.
  The Codex install is required, rather than advisory, when Canon was requested.
- Init prepares a launcher that explicitly starts Codex. Start runs in the current
  session with the existing Core scripts/templates and defaults to dry-run.

## Verification

Run `bash tests/test-install-canon-codex.sh` for installation, repeat/update,
user-file preservation, missing inputs, symlinks, paths with spaces, and a custom
Codex home. ShellCheck, shfmt, and the Skill Creator validator cover shell and
frontmatter syntax. Disabling the installer's conflict check causes the regression
test to fail.

A fresh Codex CLI session in an isolated project discovered `canon-init`, read its
bundled reference, and created `.canon/` and an executable Codex launcher, stopping
before scaffolding or trading. A second session discovered `canon-start` and correctly routed bootstrap-only
`.canon` state to phase 3 initialization without performing that action. The
generated launcher passed Bash syntax and ShellCheck validation.

The two skills were then installed locally under `~/.codex/skills/` using the
worktree installer. Full scaffold/build/dry-run and live behavior remain the next
project-level smoke test. No funding, trades, release, or changes to the existing Core/Claude install
are part of this validation. See INSTALL.md for the local skill install command.

## Canon TUI test (2026-09-17)

Launched `canon . --agent codex` in `ctest`. The installed TUI treats a leading
`$` or `!` as shell-mode activation (`toad/widgets/prompt.py:on_key`), so typing
`$canon-start` does not invoke a Codex skill through this input path.

A normal chat message, `Use the canon-start skill in this project. Stop when you
need my strategy choice.`, was forwarded intact as ACP `session/prompt`. The
adapter then returned HTTP 400: the configured `gpt-6-astra` model requires a
newer Codex version. The TUI runs `npx @zed-industries/codex-acp` (0.16.0); the
working direct CLI is 0.154.0. npm's latest adapter version was also 0.16.0 at
test time. Updating the standalone Codex CLI does not establish ACP compatibility.

The workflow did not execute through the TUI. No strategy was launched. Resolve
adapter/model compatibility and retest before recording a TUI demo. The ACP log
for the exact forwarded prompt and error is `/tmp/canon-codex-tui-skill-test.log`.

A subsequent TUI session using `codex-acp -c model="gpt-5.5"` loaded the installed
skill and shared workflow, detected the empty project, and successfully scaffolded
it. Dependency installation then encountered restricted network access. The test
was stopped before strategy selection; full dry-run validation remains pending.
The model override was session-only. This confirms the older-model path can invoke
the skill through the TUI, but does not establish demo readiness for execution.
