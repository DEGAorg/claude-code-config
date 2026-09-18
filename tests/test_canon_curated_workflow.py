"""Execute the documented phase detector against isolated project fixtures."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CuratedWorkflowTests(unittest.TestCase):
    def detect(self, *, key=None, available=True, entry=True, scaffold=True, failure=False):
        workflow = (ROOT / 'canon/commands/canon-start.md').read_text()
        phase = workflow.split('## 2. Detect phase', 1)[1]
        command = phase.split('```bash\n', 1)[1].split('```', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / 'bin'
            binary.mkdir()
            (root / 'scripts').mkdir()
            writer = root / 'scripts/terminal-ui-write.sh'
            writer.write_text('#!/bin/bash\nexit 0\n')
            choices = [{'key': 'arbiter', 'name': 'Arbiter', 'path': '/download/arbiter'}]
            canon = binary / 'canon'
            canon.write_text('#!/bin/sh\n' + ('exit 1\n' if failure else
                             "printf '%s\\n' '" + json.dumps(choices if available else []) + "'\n"))
            canon.chmod(0o755)
            pnpm = binary / 'pnpm'
            pnpm.write_text('#!/bin/sh\nexit 0\n')
            pnpm.chmod(0o755)
            if scaffold:
                for name in ('.canon/config.yaml', 'dega-core.yaml', 'package.json',
                             'tsconfig.json', 'types/TradeSignal.ts', 'types/RiskInterface.ts',
                             '.canon/agents/agent.md', '.canon/skills/skill.md'):
                    target = root / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.touch()
            if key:
                (root / 'docs').mkdir()
                (root / f'docs/strategy-{key}.md').touch()
                (root / f'strategies/{key}').mkdir(parents=True)
            if entry:
                (root / 'src').mkdir()
                (root / 'src/main.ts').touch()
            return subprocess.run(
                ['bash', '-c', command], cwd=root, text=True, capture_output=True, timeout=10,
                env={**os.environ, 'DEGA_CORE_HOME': str(root),
                     'PATH': f'{binary}:{os.environ["PATH"]}'},
            )

    def test_distributed_workflows_match(self):
        self.assertEqual((ROOT / "commands/canon-start.md").read_bytes(),
                         (ROOT / "canon/commands/canon-start.md").read_bytes())

    def test_fresh_project_initializes(self):
        self.assertEqual(self.detect(scaffold=False).stdout.strip(), 'init')

    def test_no_selection_requires_strategy_phase(self):
        self.assertEqual(self.detect().stdout.strip(), 'strategy')

    def test_old_template_document_cannot_resume(self):
        self.assertEqual(self.detect(key='arb-binary').stdout.strip(), 'strategy')

    def test_expired_access_cannot_resume(self):
        self.assertEqual(self.detect(key='arbiter', available=False).stdout.strip(), 'strategy')

    def test_verified_editable_copy_can_resume(self):
        self.assertEqual(self.detect(key='arbiter').stdout.strip(), 'run')

    def test_missing_entrypoint_requires_development(self):
        self.assertEqual(self.detect(key='arbiter', entry=False).stdout.strip(), 'develop')

    def test_access_command_failure_is_not_success(self):
        self.assertNotEqual(self.detect(key='arbiter', failure=True).returncode, 0)


if __name__ == '__main__':
    unittest.main()
