"""Keep generated Canon state out of the scaffold's initial Git commit."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ScaffoldRuntimeTests(unittest.TestCase):
    def test_initial_commit_excludes_runtime_state_and_keeps_config(self):
        git = shutil.which("git")
        self.assertIsNotNone(git)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "project"
            binary = root / "bin"
            for path in (project, binary, root / "home"):
                path.mkdir()
            # Refuse an unsafe commit even when testing the unfixed scaffold.
            # All other Git operations, including a safe initial commit, are real.
            (binary / "git").write_text(
                "#!/bin/sh\n"
                f'if [ "$1" = commit ] && "{git}" ls-files --error-unmatch '
                ".canon/state.json >/dev/null 2>&1; then\n"
                '  echo "refusing to commit generated Canon state" >&2\n'
                "  exit 99\n"
                "fi\n"
                f'exec "{git}" "$@"\n'
            )
            (binary / "curl").write_text("#!/bin/sh\nexit 98\n")
            for path in binary.iterdir():
                path.chmod(0o755)
            env = {
                "PATH": f"{binary}:{os.environ['PATH']}",
                "HOME": str(root / "home"),
                "DEGA_CORE_HOME": str(ROOT),
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_AUTHOR_NAME": "Scaffold Test",
                "GIT_AUTHOR_EMAIL": "test@example.invalid",
                "GIT_COMMITTER_NAME": "Scaffold Test",
                "GIT_COMMITTER_EMAIL": "test@example.invalid",
            }
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/canon-scaffold.sh")],
                cwd=project,
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((project / ".canon/state.json").is_file())
            tracked = subprocess.check_output(
                [git or "git", "ls-tree", "-r", "--name-only", "HEAD"],
                cwd=project,
                env=env,
                text=True,
            ).splitlines()
            self.assertNotIn(".canon/state.json", tracked)
            self.assertIn(".canon/config.yaml", tracked)
            self.assertIn(".canon/agents/dev.md", tracked)


if __name__ == "__main__":
    unittest.main()
