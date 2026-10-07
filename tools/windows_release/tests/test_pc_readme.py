import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_pipeline

class PcReadmeTests(unittest.TestCase):
    def test_current_pc_rules_not_historical_controls(self):
        text = release_pipeline.readme('0' * 40, 0)
        for expected in ['主菜单', '六轮', '最多5人', '手动EX', '90秒', '剩余总HP', '返回主菜单']:
            self.assertIn(expected, text)
        for stale in ['无需手动施放', '升级后依次解锁5人、6人']:
            self.assertNotIn(stale, text)
        self.assertIn('尚未验证', text)
