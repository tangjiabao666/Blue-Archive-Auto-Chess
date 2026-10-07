import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class MainThreadExecutionTests(unittest.TestCase):
    def test_production_never_launches_gdscript_worker_jobs(self):
        for path in (ROOT / 'core').glob('*.gd'):
            self.assertNotIn('WorkerThreadPool.', path.read_text(), str(path))
    def test_settlement_does_not_drain_synchronous_duel(self):
        self.assertNotIn('.job.run()', (ROOT / 'core/game_session.gd').read_text())
    def test_session_uses_bounded_tick_slices(self):
        source=(ROOT / 'core/game_session.gd').read_text()
        self.assertIn('entry.job.advance(1)',source)
        self.assertIn('AI_MAX_STEPS_PER_ADVANCE:=128',source)
if __name__ == '__main__':
    unittest.main()
