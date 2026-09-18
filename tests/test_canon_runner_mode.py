"""Exercise supervisor launch flags without loading a strategy or credentials."""

import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RunnerModeTests(unittest.TestCase):
    """Verify explicit command arguments own the execution mode."""

    def launch(
        self, *, arguments: tuple[str, ...] = (), environment_file: str = '',
        environment: dict[str, str] | None = None,
    ) -> tuple[list[str], str]:
        """Capture the real supervisor's invocation using a harmless executable."""
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for name in ('bin', 'src', 'home', 'core/scripts'):
                (project / name).mkdir(parents=True)
            (project / 'src/main.ts').touch()
            (project / '.env').write_text(environment_file)
            writer = project / 'core/scripts/terminal-ui-write.sh'
            writer.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> state-writes.txt\n')
            launcher = project / 'bin/pnpm'
            launcher.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$@" > captured-args.txt\nexec sleep 30\n'
            )
            launcher.chmod(0o755)
            env = {
                'HOME': str(project / 'home'),
                'PATH': f'{project / "bin"}:/usr/bin:/bin',
                'DEGA_CORE_HOME': str(project / 'core'),
                **(environment or {}),
            }
            with (project / 'output.log').open('w') as output:
                process = subprocess.Popen(
                    ['bash', str(ROOT / 'scripts/canon-runner.sh'), *arguments],
                    cwd=project, env=env, start_new_session=True,
                    stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                )
                try:
                    deadline = time.monotonic() + 5
                    captured = project / 'captured-args.txt'
                    while not captured.exists() and time.monotonic() < deadline:
                        time.sleep(0.02)
                    self.assertTrue(captured.exists(), (project / 'output.log').read_text())
                    return captured.read_text().splitlines(), (project / 'state-writes.txt').read_text()
                finally:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=5)

    def test_project_environment_cannot_enable_live_mode(self):
        args, state = self.launch(environment_file='RUN_FLAG=--live\nMODE=live\nDRY_RUN=false\n')
        self.assertEqual(args, ['exec', 'tsx', 'src/main.ts'])
        self.assertIn('metric.mode=dry-run', state)

    def test_inherited_environment_cannot_enable_live_mode(self):
        args, state = self.launch(environment={'RUN_FLAG': '--live', 'MODE': 'live'})
        self.assertEqual(args, ['exec', 'tsx', 'src/main.ts'])
        self.assertIn('metric.mode=dry-run', state)

    def test_explicit_live_mode_matches_reported_mode(self):
        args, state = self.launch(arguments=('--live',), environment_file='RUN_FLAG=\nMODE=dry-run\n')
        self.assertEqual(args, ['exec', 'tsx', 'src/main.ts', '--live'])
        self.assertIn('metric.mode=live', state)

    def test_default_without_environment_is_dry_run(self):
        args, state = self.launch()
        self.assertEqual(args, ['exec', 'tsx', 'src/main.ts'])
        self.assertIn('metric.mode=dry-run', state)


if __name__ == '__main__':
    unittest.main()
