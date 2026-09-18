"""Verify the documented wallet setup protects secrets before generation."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SecretSetupTests(unittest.TestCase):
    def test_wallet_setup_protects_old_projects_and_preserves_examples(self):
        workflow = (ROOT / "commands/canon-start.md").read_text()
        start = workflow.index("set -euo pipefail\n# Protect secrets")
        command = workflow[start:].split("```", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            (project / ".gitignore").write_text("custom-output/")
            (project / "src").mkdir()
            (project / "src/main.ts").touch()
            (project / "bin").mkdir()
            cli = project / "bin/canon-cli"
            cli.write_text(
                "#!/bin/sh\nset -e\ngit check-ignore -q .canon/wallet.env\n"
                "mkdir -p .canon\ntouch .canon/wallet.env\n"
            )
            cli.chmod(0o755)
            for _ in range(2):
                subprocess.run(
                    ["bash", "-c", command],
                    cwd=project,
                    env={**os.environ, "DEGA_CORE_HOME": directory},
                    check=True,
                )
            patterns = (project / ".gitignore").read_text().splitlines()
            self.assertIn("custom-output/", patterns)
            self.assertEqual(patterns.count(".canon/*.env"), 1)
            for name in (
                ".canon/wallet.env",
                ".env.local",
                "strategies/demo/.env",
                "strategies/demo/wallet.env",
            ):
                result = subprocess.run(
                    ["git", "check-ignore", "-q", name], cwd=project
                )
                self.assertEqual(result.returncode, 0, name)
            for name in (".env.example", "strategies/demo/.env.sample"):
                result = subprocess.run(
                    ["git", "check-ignore", "-q", name], cwd=project
                )
                self.assertEqual(result.returncode, 1, name)

    def test_scaffold_ignores_wallet_before_it_exists(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            (project / ".gitignore").write_bytes(
                (ROOT / "canon/templates/.gitignore").read_bytes()
            )
            result = subprocess.run(
                ["git", "check-ignore", "-q", ".canon/wallet.env"], cwd=project
            )
            self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
