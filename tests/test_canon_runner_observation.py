"""Verify Core observes startup output and preserves child failures without trading."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RunnerObservationTests(unittest.TestCase):
    """Run the original shell supervisor with a controlled child boundary."""

    def observe(self, *, child: str, wait_for_exit: bool = False) -> tuple[dict, int | None]:
        """Capture actual state writes in a credential-free temporary project."""
        jq = shutil.which('jq')
        if jq is None:
            self.fail('jq is required to verify the real Canon state writer')
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for name in ('bin', 'src', 'home', '.canon/execution'):
                (project / name).mkdir(parents=True)
            (project / 'src/main.ts').touch()
            (project / '.canon/execution/runner.log').write_text('NO_EDGE historical cycle\n')
            launcher = project / 'bin/pnpm'
            launcher.write_text('#!/bin/sh\n' + child)
            launcher.chmod(0o755)
            env = {
                'HOME': str(project / 'home'),
                'PATH': f'{project / "bin"}:{Path(jq).parent}:/usr/bin:/bin',
                'DEGA_CORE_HOME': str(ROOT),
            }
            with (project / 'output.log').open('w') as output:
                process = subprocess.Popen(
                    ['bash', str(ROOT / 'scripts/canon-runner.sh')],
                    cwd=project, env=env, start_new_session=True,
                    stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                )
                try:
                    if wait_for_exit:
                        process.wait(timeout=10)
                    else:
                        deadline = time.monotonic() + 4
                        state_path = project / '.canon/state.json'
                        while time.monotonic() < deadline:
                            if state_path.exists():
                                state = json.loads(state_path.read_text())
                                if state['metrics'].get('cycles') == 2:
                                    break
                            time.sleep(0.05)
                    state = json.loads((project / '.canon/state.json').read_text())
                    return state, process.poll()
                finally:
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=5)

    def test_startup_cycles_are_counted_without_replaying_history(self):
        state, exit_code = self.observe(child=(
            'echo "NO_EDGE Cycle 1 — 2 games, 3 markets, no edges"\n'
            'echo "NO_EDGE Cycle 2 — 2 games, 3 markets, no edges"\n'
            'exec sleep 30\n'
        ))
        self.assertIsNone(exit_code)
        self.assertEqual(state['metrics']['cycles'], 2)
        self.assertEqual(state['metrics']['games'], 2)
        self.assertEqual(state['metrics']['markets'], 3)

    def test_child_failure_is_reported_as_error(self):
        state, exit_code = self.observe(child='sleep 2\nexit 23\n', wait_for_exit=True)
        self.assertEqual(exit_code, 23)
        self.assertEqual(state['status'], 'error')
        self.assertIn('exit 23', state['logs'][-1]['msg'])


if __name__ == '__main__':
    unittest.main()
