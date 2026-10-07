"""Pin icon identity and original bytes independently of runtime resource imports."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
class IconIntegrity(unittest.TestCase):
    def test_verified_assets_and_complete_mapping(self):
        manifest = json.loads((ROOT / 'data/skill-icons.json').read_text())
        self.assertEqual(manifest['source']['commit'], '6f4d5bbaf93c9987bd2c1cff91581337765a1f21')
        self.assertEqual(len(manifest['characters']), 14)
        self.assertEqual(len(manifest['assets']), 37)
        for character, skills in manifest['characters'].items():
            self.assertEqual(set(skills), {'ex', 'basic', 'sub'}, character)
            for key in skills.values(): self.assertIn(key, manifest['assets'])
        for key, row in manifest['assets'].items():
            data = (ROOT / row['path'].removeprefix('res://')).read_bytes()
            self.assertEqual(len(data), row['bytes'], key)
            self.assertEqual(hashlib.sha256(data).hexdigest(), row['sha256'], key)
            self.assertEqual(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest(), row['gitBlobSha'], key)
            self.assertEqual(data[:4], b'RIFF')
            self.assertEqual(data[8:12], b'WEBP')
            x0, y0, x1, y1 = row['alphaBounds']
            width, height = row['dimensions']
            self.assertTrue(0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height)
    def test_exact_specialized_symbols(self):
        chars = json.loads((ROOT / 'data/skill-icons.json').read_text())['characters']
        self.assertEqual(chars['shiroko']['ex'], 'skill/SKILLICON_SHIROKO_EXSKILL')
        self.assertEqual(chars['aris']['basic'], 'skill/SKILLICON_ARIS_PUBLICSKILL')
        self.assertEqual(chars['mutsuki']['ex'], 'skill/SKILLICON_MUTSUKI_EXSKILL')
        self.assertEqual(chars['koharu']['ex'], 'skill/SKILLICON_KOHARU_EXSKILL')
        self.assertEqual(chars['hina']['ex'], chars['hoshino']['ex'])
if __name__ == '__main__': unittest.main()
