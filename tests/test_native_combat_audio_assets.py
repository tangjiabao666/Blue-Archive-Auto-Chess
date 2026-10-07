"""Validate shipped bytes and binding coverage independently of the audio player.

Optional source manifest path proves exact original timing, parameters and IDs.
The standalone default validates packaged manifest, WAV identity and safe subset.
"""
import hashlib
import json
from pathlib import Path
import sys
import wave
from asuna_audio_activation_boundary import validate

def main():
    ROOT = Path(__file__).resolve().parents[1]
    data = json.loads((ROOT / 'data/audio/native-skill-sfx.json').read_text())
    rows = data['records']
    validate(json.loads((ROOT / 'data/audio/native-ordinary-sfx.json').read_text()), data, ROOT)
    original_keys = {'shiroko', 'hoshino', 'hina', 'aru', 'yuuka', 'aris', 'serika'}
    original_rows = [r for r in rows if r['character'] in original_keys]
    assert len(original_rows) == 12
    assert sum(r['timelineKind'] == 'ex' for r in original_rows) == 11
    assert [(r['character'], r['timelineKind']) for r in original_rows if r['timelineKind'] == 'basic'] == [('aris', 'basic')]
    assert original_keys.issubset({r['character'] for r in rows})
    assert len(rows) == data['counts']['rows']
    source = json.loads(Path(sys.argv[1]).read_text()) if len(sys.argv) > 1 else None
    coverage = []
    for row in rows:
        assert row['currentSimSelectable'] and not row['muted'] and not row['loop']
        assert row['pitch'] > 0 and row['timeScale'] > 0
        assert len(row['nativeAudioData']['AudioClips']) == 1
        assert row['nativeAudioData']['AudioClips'][0] == row['sourceAudioClip']
        wav = ROOT / row['resourcePath'].removeprefix('res://')
        assert hashlib.sha256(wav.read_bytes()).hexdigest() == row['wavSHA256']
        with wave.open(str(wav)) as audio:
            assert audio.getsampwidth() == 2 and audio.getcomptype() == 'NONE'
            duration = audio.getnframes() / audio.getframerate()
        assert abs(duration - row['wavDurationSeconds']) < 1e-10
        assert abs(duration - row['nativeDurationSeconds']) < 1e-5
        if source and row['character'] != 'asuna':
            matches = [e for e in source['timelines']
                       if e['timelineSource'] == row['sourceTimeline'] and e['asset'] == row['sourceController']]
            assert len(matches) == 1
            original = matches[0]
            assert original['bindingStatus'] == 'exact_all_clips_decoded'
            assert original['character'] == row['character'] and original['kind'] == row['timelineKind']
            for source_key, target_key in [('startSeconds','startSeconds'),('durationSeconds','trackWindowSeconds'),('clipInSeconds','clipInSeconds'),('timeScale','timeScale')]:
                assert original[source_key] == row[target_key]
            assert original['parameters']['AudioData'] == row['nativeAudioData']
            for source_key, target_key in [('Volume','volumeLinear'),('Pitch','pitch'),('Delay','delaySeconds'),('Loop','loop')]:
                assert original['parameters']['AudioData'][source_key] == row[target_key]
            assert original['boundClips'][0]['source'] == row['sourceAudioClip']
        coverage.append({'character':row['character'],'kind':row['timelineKind'],'clip':row['clipName'],
                         'onset':row['startSeconds'],'pitch':row['pitch'],'volume':row['volumeLinear'],
                         'duration':duration,'window':row['trackWindowSeconds'],'sha256':row['wavSHA256']})
    assert len(set(r['resourcePath'] for r in rows)) == data['counts']['uniqueWAVs']
    print(json.dumps({'result':'PASS','live_events':len(rows),'ex_events':sum(r['timelineKind']=='ex' for r in rows),'basic_events':sum(r['timelineKind']=='basic' for r in rows),
                      'unique_wavs':data['counts']['uniqueWAVs'],'bytes':sum((ROOT / r['resourcePath'].removeprefix('res://')).stat().st_size for r in rows),
                      'exact_original_manifest_compared':bool(source),'exact_activation_inverse_compared':True,'original_13_source_digest_preserved':True,'coverage':coverage},indent=2))

if __name__ == "__main__":
    main()
