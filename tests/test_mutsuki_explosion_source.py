"""Verify recovered GLES, archived draft arithmetic, and immutable source art.

The archived draft is NOT registered for runtime use: vertex input parity is unresolved.

Only stdlib is needed. LZ4 here decodes the supplied raw shader block, not an
external stream or an installed executable. Source JSON is never modified.
"""
import hashlib
import json
import pathlib
import re
import struct
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/effects/resources/CAB-38d7f184c16228480d78cd7ea10cae27/Shader-5422753266744534315.json'
SHADER = ROOT / 'evidence/mutsuki-explosion-source/unverified-native-port.gdshader.txt'
EVIDENCE = ROOT / 'evidence/mutsuki-explosion-source'


def decode_lz4(block, expected):
    out = bytearray()
    cursor = 0
    while cursor < len(block):
        token = block[cursor]
        cursor += 1
        literals = token >> 4
        if literals == 15:
            while True:
                extra = block[cursor]
                cursor += 1
                literals += extra
                if extra != 255:
                    break
        out.extend(block[cursor:cursor + literals])
        cursor += literals
        if cursor == len(block):
            break
        offset = struct.unpack_from('<H', block, cursor)[0]
        cursor += 2
        assert 0 < offset <= len(out)
        count = (token & 15) + 4
        if (token & 15) == 15:
            while True:
                extra = block[cursor]
                cursor += 1
                count += extra
                if extra != 255:
                    break
        for _ in range(count):
            out.append(out[-offset])
    assert len(out) == expected
    return bytes(out)


def source_program(index=1):
    tree = json.loads(SOURCE.read_text())
    platform = tree['platforms'].index(9)
    offset = tree['offsets'][platform][0]
    size = tree['compressedLengths'][platform][0]
    raw = decode_lz4(bytes(tree['compressedBlob'][offset:offset + size]), tree['decompressedLengths'][platform][0])
    start, length, segment = struct.unpack_from('<iii', raw, 4 + 12 * index)
    assert segment == 0
    program = raw[start:start + length]
    start = program.index(b'#ifdef VERTEX')
    length = struct.unpack_from('<i', program, start - 4)[0]
    text = program[start:start + length].rstrip(b'\0').decode()
    return text[:text.rindex('#endif') + 6] + '\n'


def normalized(text):
    return re.sub(r'\s+', '', text)


class MutsukiExplosionSourceTests(unittest.TestCase):
    def test_forward_program_is_exact_recovered_source(self):
        self.assertEqual(source_program(), (EVIDENCE / '9-1.glsl').read_text())
        tree = json.loads(SOURCE.read_text())
        forward = tree['m_ParsedForm']['m_SubShaders'][0]['m_Passes'][0]
        self.assertEqual(forward['m_State']['m_Name'], 'Forward')
        selected = forward['progVertex']['m_PlayerSubPrograms'][3][0]
        self.assertEqual((selected['m_BlobIndex'], selected['m_GpuProgramType']), (1, 4))

    def test_archived_draft_preserves_original_statements_only(self):
        self.assertTrue(SHADER.exists(), 'the rejected prototype remains available for source audit')
        original = source_program()
        translated = SHADER.read_text()
        fragment = original.split('#ifdef FRAGMENT')[1].split('void main()')[1]
        statements = fragment.split('{', 1)[1].split('return;')[0]
        self.assertIn(normalized(statements), normalized(translated))
        vertex = original.split('#ifdef FRAGMENT')[0].split('void main()')[1]
        displacement = vertex.split('{', 1)[1].split('u_xlat1.xyz =')[0]
        self.assertIn(normalized(displacement), normalized(translated))
        self.assertIn('VERTEX = u_xlat0.xyz;', translated)
        self.assertIn('vec3 in_NORMAL0 = NORMAL;', translated)
        self.assertIn('vec4 in_TEXCOORD1 = custom0;', translated)
        self.assertIn('vec4 vs_TEXCOORD3 = custom0;', translated)
        self.assertIn('ALBEDO = SV_Target0.rgb;', translated)
        self.assertIn('ALPHA = SV_Target0.a;', translated)
        self.assertNotIn('source_color', translated)  # Adapter applies each source texture's flag.
        self.assertNotIn('particle_color.rgb', translated)  # Original program ignores vertex color.

    def test_source_receipt_preserves_all_native_assets(self):
        receipt = json.loads((EVIDENCE / 'source-receipt.json').read_text())
        for relative, expected in receipt['source_sha256'].items():
            with self.subTest(path=relative):
                self.assertEqual(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest(), expected)


if __name__ == '__main__':
    unittest.main()
