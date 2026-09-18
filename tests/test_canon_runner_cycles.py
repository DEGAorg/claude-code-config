"""Verify completed cycles remain independent of their signal count."""

import unittest

from tests import test_canon_runner_observation


class RunnerCycleTests(unittest.TestCase):
    """Observe generic cycle records through the actual shell supervisor."""

    def test_successful_cycles_count_once_independently_of_signals(self):
        state, exit_code = (
            test_canon_runner_observation.RunnerObservationTests().observe(
                child=(
                    'echo "SCAN Cycle 1 started"\n'
                    'echo "SIGNAL First opportunity"\n'
                    'echo "CYCLE Cycle 1 — 2 games, 3 markets, 1 signal"\n'
                    'echo "SCAN Cycle 2 started"\n'
                    'echo "SIGNAL Second opportunity"\n'
                    'echo "SIGNAL Third opportunity"\n'
                    'echo "CYCLE Cycle 2 — 4 games, 5 markets, 2 signals"\n'
                    "exec sleep 30\n"
                )
            )
        )
        self.assertIsNone(exit_code)
        self.assertEqual(state["metrics"]["cycles"], 2)
        self.assertEqual(state["metrics"]["signals"], 3)
        self.assertEqual(state["metrics"]["games"], 4)
        self.assertEqual(state["metrics"]["markets"], 5)
        self.assertEqual(state["metrics"]["errors"], 0)


if __name__ == "__main__":
    unittest.main()
