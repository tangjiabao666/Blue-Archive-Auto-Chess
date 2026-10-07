"""Actual inactive fixture resources must be verified in source and isolated PCK."""
from pathlib import Path
import unittest
from test_pipeline import load_module,HERE
class AsunaFixtureDependencies(unittest.TestCase):
 def test_nested_private_fixture_is_part_of_raw_dependency_manifest(self):
  dependency=load_module('dependency_manifest')
  manifest=dependency.build_manifest(HERE.parents[1])
  raw={row['path'] for row in manifest['files'] if row['category']=='runtime_json'}
  self.assertIn('data/effects/asuna/battle-events-compact.json',raw)
  self.assertIn('data/effects/asuna/asuna/visual-templates.json',raw)
  self.assertEqual(manifest['summary']['counts']['mesh_raw'],171)
  self.assertEqual(manifest['summary']['counts']['vfx_texture_png'],279)
  self.assertEqual(manifest['summary']['counts']['vfx_texture_json'],279)
  self.assertEqual(len(manifest['summary']['active_roster']),14)
  self.assertEqual(manifest['summary']['active_roster'][-1],'asuna')
if __name__=='__main__':unittest.main()
