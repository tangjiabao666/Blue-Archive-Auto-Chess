"""A bounded import exception must never weaken runtime/export diagnostics."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

HERE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(HERE))
spec=importlib.util.spec_from_file_location('android_diagnostic_pipeline',HERE/'release_pipeline.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)

ERROR='ERROR: Basis [X: (0.0, 0.0, 0.0), Y: (0.0, 0.0, 0.0), Z: (0.0, 0.0, 0.0)] must be normalized in order to be casted to a Quaternion. Use get_rotation_quaternion() or call orthonormalized() if the Basis contains linearly independent vectors.'
TRACE='   at: get_quaternion (core/math/basis.cpp:716)'
def fixture(count=6):
    return '[ 99% ] reimport | shiroko_drone.glb\n[ 0% ] import | Importing Scene...\n'+(ERROR+'\n'+TRACE+'\n')*count+'[ DONE ] import\n'

class DiagnosticGate(unittest.TestCase):
    def classify(self,text,phase):
        self.assertTrue(hasattr(p,'classify_godot_diagnostics'),'Missing bounded import diagnostic gate')
        return p.classify_godot_diagnostics(text,phase)
    def test_exact_six_in_drone_import_are_preserved(self):
        report=self.classify(fixture(),'import')
        self.assertTrue(report['passed'],report)
        self.assertEqual(report['accepted_count'],6)
        self.assertEqual(len(report['diagnostics']),6)
        self.assertEqual(report['diagnostics'][0]['message'],ERROR)
    def test_runtime_and_export_never_accept_the_same_diagnostics(self):
        for phase in ['export','audio','runtime','']:
            self.assertFalse(self.classify(fixture(),phase)['passed'])
    def test_counts_context_messages_and_stack_must_match_exactly(self):
        for text in [fixture(5),fixture(7),fixture().replace('shiroko_drone.glb','other.glb'),fixture().replace(':716',':717'),fixture().replace('X: (0.0,','X: (1.0,'),fixture()+'WARNING: unexpected\n',fixture().replace('[ 0% ] import | Importing Scene...','[ DONE ] import')]:
            self.assertFalse(self.classify(text,'import')['passed'],text)
    def test_unmatched_drone_inputs_fail_before_validation(self):
        self.assertTrue(hasattr(p,'validate_drone_inputs'),'Missing exact drone input gate')
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            model=root/'assets/skill_props/shiroko_drone/shiroko_drone.glb'
            model.parent.mkdir(parents=True);model.write_bytes(b'tampered')
            with self.assertRaises(ValueError):p.validate_drone_inputs(root)

    def test_clean_logs_and_ansi_context(self):
        self.assertTrue(self.classify('clean\n','export')['passed'])
        self.assertEqual(self.classify('clean\n','export')['accepted_count'],0)
        self.assertTrue(self.classify(fixture().replace('reimport','\x1b[1mreimport\x1b[22m'),'import')['passed'])

if __name__=='__main__':unittest.main()
