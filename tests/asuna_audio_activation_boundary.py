"""Exact additive activation inverse. Never weakens original 13-character guards."""
from pathlib import Path
import copy,hashlib,json,wave
FIX=Path(__file__).parent/'fixtures'
PINS={'ordinary':'0972fcc4254796cefbedcb7a52174e1bed6968f4c63fdc0a1e1daa46ca431438','skill':'b16764f0ac64d25ec402a6dbb8e2f6e716a7ad1ec6ac2c508c089626ab95eae4','delta':'bd37c57d1bd0fda3bd93fd2b530382565ec9c0ac5f5b643a3d8416ca24f34037'}
OLD_13_ROWS_SHA='fbdc597411aa331e479b93946bd0e909b31d76c000823486a46955ef9ba65de1'
def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(d):return json.dumps(d,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def fail(ok,message):
 if not ok:raise ValueError(message)
def no_duplicate_keys(pairs):
 d={}
 for k,v in pairs:
  fail(k not in d,'duplicate JSON key: '+k);d[k]=v
 return d
def strict_json(text):return json.loads(text,object_pairs_hook=no_duplicate_keys)
def fixture(kind):
 p=FIX/('asuna_audio_activation_delta.json' if kind=='delta' else f'asuna_audio_before_{kind}.json');b=p.read_bytes();fail(sha(b)==PINS[kind],kind+' frozen fixture changed');return strict_json(b)
def validate(ordinary,skill,root=None):
 oldo=fixture('ordinary');olds=fixture('skill');delta=fixture('delta');o=copy.deepcopy(ordinary);s=copy.deepcopy(skill)
 fail(isinstance(o,dict) and isinstance(s,dict),'manifest object required')
 fail(set(o)==set(oldo)|{'asunaActivationProvenance'},'ordinary exact top-level fields')
 fail(set(s)==set(olds)|{'asunaActivationProvenance'},'skill exact top-level fields')
 for d in [o,s]:fail(canonical(d.pop('asunaActivationProvenance'))==canonical(delta['provenance']),'exact activation provenance')
 fail(type(o.get('assets')) is dict and len(o['assets'])==96,'exact 96 ordinary assets')
 fail(type(o.get('bindings')) is list and len(o['bindings'])==28,'exact 28 ordinary bindings')
 fail(canonical(o['bindings'][-2:])==canonical(delta['ordinaryBindings']),'exact appended Asuna ordinary rows/order/source fields')
 o['bindings']=o['bindings'][:-2]
 for name,row in delta['ordinaryAssets'].items():
  fail(name in o['assets'] and canonical(o['assets'][name])==canonical(row),'exact added ordinary asset '+name);del o['assets'][name]
 fail(sha(canonical(sorted(o['bindings'],key=lambda r:r['binding_id'])))==OLD_13_ROWS_SHA,'unchanged original 26-row source digest')
 fail(len({r['character'] for r in ordinary['bindings']})==14,'exact 14 ordinary characters')
 fail(len({a['path'] for a in ordinary['assets'].values()})==96,'exact 96 unique ordinary WAV paths')
 fail(type(s.get('records')) is list and len(s['records'])==48,'exact 48 skill records')
 fail(canonical(s['records'][-3:])==canonical(delta['skillRecords']),'exact appended Asuna EX rows/order/source values')
 s['records']=s['records'][:-3]
 expected_counts=copy.deepcopy(olds['counts']);expected_counts.update(rows=48,currentlySelectable=48,uniqueWAVs=43)
 fail(canonical(s['counts'])==canonical(expected_counts),'exact activated skill counts and preserved count metadata')
 for k in ['rows','currentlySelectable','uniqueWAVs']:fail(type(s['counts'][k]) is int,'integer count '+k)
 s['counts']=copy.deepcopy(olds['counts'])
 fail(len({r['resourcePath'] for r in skill['records']})==43,'exact 43 unique skill WAV paths')
 fail(canonical(o)==canonical(oldo),'ordinary inverse changes original rows/assets/source/adapter metadata')
 fail(canonical(s)==canonical(olds),'skill inverse changes original records/source/adapter metadata')
 # The original manifests' formatting also round-trips byte-for-byte after inverse.
 for key,d in [('ordinary',o),('skill',s)]:
  encoded=(json.dumps(d,indent=2,ensure_ascii=False)+('\n' if key=='ordinary' else '')).encode();fail(sha(encoded)==PINS[key],key+' exact original manifest byte inverse')
 for r,source in zip(delta['ordinaryBindings'],delta['selectedOrdinarySourceRecords']):
  fail(sha(canonical(source))==r['source_row_sha256'],'source identity row hash');fail(r['clips']==source['audio_clip_path'] and r['raw_volume']==source['volume'] and r['raw_delay']==source['delay'],'genuine source gain/delay/pool')
 for r,source in zip(delta['skillRecords'],delta['selectedSkillSourceEvents']):
  data=source['controller_data']['AudioData'];tc=source['timeline_clip'];ref=source['audio_references'][0]
  for original,field in [('Volume','volumeLinear'),('Pitch','pitch'),('Delay','delaySeconds')]:fail(canonical(data[original])==canonical(r[field]),'genuine EX source '+field)
  for original,field in [('m_Start','startSeconds'),('m_Duration','trackWindowSeconds'),('m_ClipIn','clipInSeconds'),('m_TimeScale','timeScale')]:fail(canonical(tc[original])==canonical(r[field]),'genuine EX source '+field)
  fail(r['sourceAudioClip']['cab']==ref['cab'] and r['sourceAudioClip']['pathId']==ref['path_id_decimal'],'genuine EX clip CAB/pathID')
  fail(r['sourceController']['pathId']==source['controller_source']['path_id_decimal'],'genuine EX controller identity')
  for field,value in data.items():
   if field not in ['AudioClips','AudioMixerGroup','AudioMixerSnapshot']:fail(canonical(r['nativeAudioData'][field])==canonical(value),'genuine preserved AudioData '+field)
 if root is not None:
  for name,row in ordinary['assets'].items():
   p=Path(root)/row['path'].removeprefix('res://');fail(sha(p.read_bytes())==row['wav_sha256'],'ordinary original/new WAV hash '+name)
   with wave.open(str(p)) as w:fail(sha(w.readframes(w.getnframes()))==row['pcm_sha256'],'ordinary original/new PCM '+name)
  for row in skill['records']:
   p=Path(root)/row['resourcePath'].removeprefix('res://');fail(sha(p.read_bytes())==row['wavSHA256'],'skill original/new WAV '+row['clipName'])
   with wave.open(str(p)) as w:fail(sha(w.readframes(w.getnframes()))==row['pcmDataSHA256'],'skill original/new PCM '+row['clipName'])
 return {'ordinary_assets':96,'ordinary_bindings':28,'characters':14,'skill_records':48,'skill_wavs':43,'old13_source_digest':OLD_13_ROWS_SHA,'old_manifest_byte_inverse':True}
