"""Execute documented Canon phase blocks against isolated external boundaries."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / "canon/commands/canon-start.md"


class WalletBoundaryTests(unittest.TestCase):
    def exercise(self, section: str, *, entry: bool, allow_wallet: bool):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for name in ("bin", "scripts", "home"):
                (project / name).mkdir()
            if entry:
                (project / "src").mkdir()
                (project / "src/main.ts").touch()
            (project / ".gitignore").touch()
            subprocess.run(["git", "init", "-q"], cwd=project, check=True)
            scripts = {
                "scripts/terminal-ui-write.sh": "echo state >> calls\n",
                "scripts/canon-scaffold.sh": "echo scaffold >> calls\n",
                "bin/pnpm": 'echo "pnpm $*" >> calls\n',
                "bin/canon-cli": (
                    'echo "wallet $*" >> calls\n'
                    + ("exit 0\n" if allow_wallet else "exit 88\n")
                ),
                "scripts/canon-live-readiness.sh": "echo live-preflight >> calls\n",
            }
            for name, body in scripts.items():
                path = project / name
                path.write_text("#!/bin/sh\n" + body)
                path.chmod(0o755)
            env = {
                "HOME": str(project / "home"),
                "PATH": f"{project / 'bin'}:{os.environ['PATH']}",
                "DEGA_CORE_HOME": str(project),
            }
            results = []
            for command in re.findall(r"```bash\n(.*?)```", section, re.DOTALL):
                result = subprocess.run(
                    ["bash", "-c", command],
                    cwd=project,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                results.append(result.returncode)
                if result.returncode:
                    break
            calls_path = project / "calls"
            calls = calls_path.read_text().splitlines() if calls_path.exists() else []
            return results, calls, (project / ".canon/wallet.env").exists()

    def test_dry_run_init_installs_without_wallet_or_live_calls(self):
        section = (
            WORKFLOW.read_text().split("## 3. Phase: init", 1)[1].split("## 4.", 1)[0]
        )
        results, calls, wallet_exists = self.exercise(
            section, entry=False, allow_wallet=False
        )
        self.assertTrue(results)
        self.assertTrue(all(code == 0 for code in results), calls)
        self.assertIn("pnpm install --frozen-lockfile", calls)
        self.assertIn("scaffold", calls)
        self.assertFalse(
            any("wallet" in call or "live-preflight" in call for call in calls)
        )
        self.assertFalse(wallet_exists)

    def test_live_phase_keeps_wallet_setup_before_existing_preflight(self):
        section = WORKFLOW.read_text().split("## 8. Phase: live", 1)[1]
        self.assertLess(
            section.index("recheck the selected key"), section.index("wallet ensure")
        )
        results, calls, _ = self.exercise(section, entry=True, allow_wallet=True)
        self.assertEqual(results, [0, 0])
        self.assertEqual(calls, ["wallet wallet ensure --pretty", "live-preflight"])

    def test_live_transition_without_a_built_entry_creates_no_wallet(self):
        section = WORKFLOW.read_text().split("## 8. Phase: live", 1)[1]
        results, calls, wallet_exists = self.exercise(
            section, entry=False, allow_wallet=True
        )
        self.assertEqual(results, [1])
        self.assertEqual(calls, [])
        self.assertFalse(wallet_exists)


if __name__ == "__main__":
    unittest.main()
