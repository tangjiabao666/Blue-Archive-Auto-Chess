"""Keep the packaged canonical-save gate aligned with the runtime schemas."""
from pathlib import Path
import re
import unittest


HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parents[1]


class PackagedSaveVersions(unittest.TestCase):
    def test_canonical_save_gate_uses_session_version_and_pins_rules_version(self):
        verifier = (HERE / 'verify_runtime.gd').read_text()
        gate = re.search(
            r'ck\(([^\n]+),"packaged canonical preparation saves"\)', verifier)
        self.assertIsNotNone(gate, 'canonical preparation save gate is missing')
        # Session migrations change the canonical envelope without changing
        # Rules6. The package must follow that canonical version, not a literal.
        self.assertRegex(gate.group(1),
                         r'\bsave\.data\.version\s*==\s*Session\.SAVE_VERSION\b')
        self.assertRegex(gate.group(1), r'\bsave\.data\.rules\.version\s*==\s*6\b')
        rules = (ROOT / 'core/prototype_match.gd').read_text()
        self.assertRegex(rules, r'\bconst\s+VERSION\s*:?=\s*6\b')


if __name__ == '__main__':
    unittest.main()
