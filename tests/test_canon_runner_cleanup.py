"""Verify stopping Canon reaps its monitoring descendants immediately."""

import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RunnerCleanupTests(unittest.TestCase):
    def test_supervisor_shutdown_reaps_watcher_sleep(self):
        jq = shutil.which("jq")
        self.assertIsNotNone(jq, "jq is required for the actual Canon state writer")
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for name in ("src", "bin", "home"):
                (project / name).mkdir()
            (project / "src/main.ts").touch()
            launcher = project / "bin/pnpm"
            launcher.write_text("#!/bin/sh\nexec sleep 30\n")
            launcher.chmod(0o755)
            env = {
                "PATH": f"{project / 'bin'}:{Path(jq or '').parent}:/usr/bin:/bin",
                "HOME": str(project / "home"),
                "DEGA_CORE_HOME": str(ROOT),
            }
            with (project / "output.log").open("w") as output:
                process = subprocess.Popen(
                    ["bash", str(ROOT / "scripts/canon-runner.sh")],
                    cwd=project,
                    env=env,
                    start_new_session=True,
                    stdin=subprocess.DEVNULL,
                    stdout=output,
                    stderr=subprocess.STDOUT,
                )
                try:
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline:
                        if any(
                            line.rstrip().endswith("sleep 3")
                            for line in self.group_members(process.pid)
                        ):
                            break
                        time.sleep(0.025)
                    self.assertTrue(
                        any(
                            line.rstrip().endswith("sleep 3")
                            for line in self.group_members(process.pid)
                        ),
                        "watcher must be sleeping before shutdown",
                    )
                    process.send_signal(signal.SIGTERM)
                    self.assertEqual(process.wait(timeout=5), 143)
                    self.assertEqual(self.group_members(process.pid), [])
                finally:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=5)

    @staticmethod
    def group_members(group: int) -> list[str]:
        output = subprocess.check_output(
            ["ps", "-axo", "pid=,pgid=,stat=,command="], text=True
        )
        return [
            line
            for line in output.splitlines()
            if len(line.split(None, 3)) >= 4 and line.split(None, 3)[1] == str(group)
        ]


if __name__ == "__main__":
    unittest.main()
