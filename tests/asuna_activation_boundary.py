import json,hashlib
BASE_SHA256='56df83cd301065938eb75fc116ccded77024b38a05b53911eb8bf20aaf383860'
OLD_ACTIVE=['shiroko', 'hoshino', 'hina', 'aru', 'yuuka', 'aris', 'serika', 'iori', 'tsubaki', 'nonomi', 'mutsuki', 'haruna', 'koharu']
OLD_NOTE='Thirteen active board characters retain the original seven and add Iori, Tsubaki, Nonomi, Mutsuki, Haruna and Koharu with source-backed mechanics and native presentations. Shop gold prices are explicit autochess adaptations in game_session.gd, distinct from preserved source EX energy costs. Serina remains a historical/future off-field support record outside the active roster. Asuna is an inactive base numerical record pending separate combat, presentation and release gates; active roster and active count remain thirteen.'
NEW_NOTE='Fourteen active board characters: the original thirteen plus Asuna. Source numerical records and EX energy costs remain unchanged; shop prices and automatic skill scheduling are autochess adaptations. Serina remains a historical/future off-field support record. Particle, audio and rendering fidelity limitations are documented; no Unity pixel-perfect parity is claimed.'
def _parse(raw):
 def unique(pairs):
  result={}
  for key,value in pairs:
   if key in result:raise AssertionError('duplicate JSON key: '+key)
   result[key]=value
  return result
 return json.loads(raw,object_pairs_hook=unique)
def _bytes(data):return (json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode()
def _sha(raw):return hashlib.sha256(raw if isinstance(raw,bytes) else raw.encode()).hexdigest()
def activate(raw):
 if _sha(raw)!=BASE_SHA256:raise AssertionError('wrong inactive activation baseline')
 data=_parse(raw)
 data['active_roster']=OLD_ACTIVE+['asuna'];data['activeRosterCount']=14
 data['pending_native_roster']=[];data['rosterNote']=NEW_NOTE
 return _bytes(data)
def reverse_activation(raw):
 try:
  data=_parse(raw)
  if data['active_roster']!=OLD_ACTIVE+['asuna']:raise AssertionError('exact fourteen-character order required')
  if type(data['activeRosterCount']) is not int or data['activeRosterCount']!=14:raise AssertionError('exact integer fourteen required')
  if data['pending_native_roster']!=[] or data['rosterNote']!=NEW_NOTE:raise AssertionError('activation metadata changed')
  data['active_roster']=OLD_ACTIVE;data['activeRosterCount']=13
  data['pending_native_roster']=['asuna'];data['rosterNote']=OLD_NOTE
  restored=_bytes(data)
  if _sha(restored)!=BASE_SHA256:raise AssertionError('unapproved source changes beyond activation')
  return restored
 except (KeyError,TypeError,ValueError) as error:raise AssertionError('malformed activation data') from error
