"""Reverse only the reviewed inactive-Asuna numerical additions.

Each removed/replaced value is checked before inversion. The reconstructed
complete historical file must match its immutable pre-Asuna hash, so unexpected
old-character, active-roster, source-metadata or extra-field edits fail closed.
This numerical helper does not erase any runtime/core source changes.
"""
import hashlib
import json

PRE_ASUNA_DATA_SHA256 = 'd58847d79ffd7eac1e8721a68782931f5d2b53b7a5a92c6f188a0528620944ca'
ASUNA_CHARACTER_SHA256 = 'f4f4ae538684b5fb43e241d1c20f1f745b464f52ab0318dab0310d73a6f031b7'
ASUNA_FRAMES_SHA256 = '9c4864b95156b184fb064ddee86712046c011e5e2ba43e01399b6298ac429625'
ADDED_METADATA_SHA256 = {
    'asunaSourceSnapshot': '7ef10a389d576211f5cfe9bf2cd04c8fc5f64f3bee9bd4f3a61033291b201d92',
    'asunaRuntimeAdaptations': 'f273557208984830840afab0859aaccecae331f2d0c94de521e59c5f819b710b',
    'asunaSourceFormulaReferenceValues': '967c997a895ff072f8dc9708912fd17164e2e8d481de12188fab2faa73e4d9f3',
}
ASUNA_NOTE_SUFFIX = ' Asuna is an inactive base numerical record pending separate combat, presentation and release gates; active roster and active count remain thirteen.'


def _no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result: raise AssertionError('duplicate JSON key: ' + key)
        result[key] = value
    return result


def _digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def reverse_asuna_data(source):
    """Return original JSON bytes only if all approved seams verify exactly."""
    try:
        data = json.loads(source, object_pairs_hook=_no_duplicate_keys)
        chars = data['characters']
        if len(chars) != 15 or [c['key'] for c in chars].count('asuna') != 1:
            raise AssertionError('expected exactly fifteen records including one Asuna')
        if chars[-1]['key'] != 'asuna' or _digest(chars[-1]) != ASUNA_CHARACTER_SHA256:
            raise AssertionError('approved final Asuna record changed')
        if _digest(data['runtimeSourceFrames']['asuna']) != ASUNA_FRAMES_SHA256:
            raise AssertionError('approved Asuna runtime frames changed')
        for key, expected in ADDED_METADATA_SHA256.items():
            if _digest(data[key]) != expected: raise AssertionError('approved Asuna metadata changed: ' + key)
        if type(data['rosterRecordCount']) is not int or data['rosterRecordCount'] != 15:
            raise AssertionError('expected total count exactly integer fifteen')
        if data['pending_native_roster'] != ['asuna']:
            raise AssertionError('expected inactive Asuna pending roster only')
        if not data['rosterNote'].endswith(ASUNA_NOTE_SUFFIX):
            raise AssertionError('approved Asuna roster note suffix changed')
        data['characters'] = chars[:-1]
        del data['runtimeSourceFrames']['asuna']
        for key in ADDED_METADATA_SHA256: del data[key]
        data['rosterRecordCount'] = 14
        data['pending_native_roster'] = []
        data['rosterNote'] = data['rosterNote'][:-len(ASUNA_NOTE_SUFFIX)]
        restored = (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode()
        if hashlib.sha256(restored).hexdigest() != PRE_ASUNA_DATA_SHA256:
            raise AssertionError('unapproved historical numerical data changed')
        return restored
    except (KeyError, IndexError, TypeError, ValueError, AttributeError) as error:
        raise AssertionError('missing or malformed approved Asuna data seam') from error
