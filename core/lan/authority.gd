extends RefCounted
const Rules=preload('res://core/lan/room_rules.gd')
const Duel=preload('res://core/lan/duel_runtime.gd')
const Offscreen=preload('res://core/offscreen_duel.gd')
const Pacing=preload('res://core/battle_pacing.gd')
var rules=Rules.new()
var duels:Dictionary={}
var ai_jobs:Array=[]
var controller_epochs:Dictionary={}
var _last_request:Dictionary={}
var _last_ack:Dictionary={}
var _frozen:Dictionary={}
var _loaded:Dictionary={}
var _continue:Dictionary={}
var _participant_duel:Dictionary={}
var last_error:=''
func start_match(seed:int)->Dictionary:
 close();last_error='';controller_epochs={};_last_request.clear();_last_ack.clear()
 var result:Dictionary=rules.new_match(seed,['p0','p1','p2'])
 if result.ok:
  for id in ['p0','p1','p2']:controller_epochs[id]=0
 return result
func submit_intent(participant_id:String,request:Dictionary)->Dictionary:
 if rules.controllers.get(participant_id)!='human':return {'ok':false,'error':'not_controller'}
 if request.size()!=4 or not request.has('round') or not request.has('controller_epoch') or not request.has('sequence') or not request.get('command') is Dictionary:return {'ok':false,'error':'invalid_request'}
 for field in ['round','controller_epoch','sequence']:
  if not request[field] is int or request[field]<0:return {'ok':false,'error':'invalid_request'}
 if request.round!=rules._state.round or request.controller_epoch!=controller_epochs[participant_id]:return {'ok':false,'error':'stale_context'}
 if request.sequence==_last_request.get(participant_id,-1):return _last_ack[participant_id].duplicate(true)
 if request.sequence<int(_last_request.get(participant_id,-1)):return {'ok':false,'error':'stale_request'}
 var command:Dictionary=request.command;var result:Dictionary
 if command.get('type')=='ready' and command.size()==2 and command.get('value') is bool:
  result=rules.set_ready(participant_id,command.value)
  if result.ok and rules.ready.values().all(func(value):return value):result=begin_round()
 elif command.get('type') in ['cast_ex','move']:
  if rules._state.phase!='battle' or not _participant_duel.has(participant_id):result={'ok':false,'error':'wrong_phase'}
  else:
   var duel=duels[_participant_duel[participant_id]]
   result=duel.queue_intent(0 if duel.pair.left_id==participant_id else 1,command)
 else:result=rules.execute_for(participant_id,command)
 _last_request[participant_id]=request.sequence;_last_ack[participant_id]=result.duplicate(true);return result
func begin_round()->Dictionary:
 var frozen:Dictionary=rules.freeze_round()
 if not frozen.ok:return frozen
 _frozen=frozen;_loaded.clear();_continue.clear();_participant_duel.clear()
 for duel in duels.values():duel.close()
 duels.clear();ai_jobs.clear()
 for index in range(frozen.pairs.size()):
  var pair:Array=frozen.pairs[index];var left:String=pair[0];var right:String=pair[1]
  var settings:Dictionary=Pacing.options(3)
  settings.merge({'seed':Offscreen.derive_seed(int(frozen.seed),int(frozen.round),left,right),'combat_mode':'tactical_v1','arena_half':frozen.arena.half_size,'area_ex_coverage_targeting':true,'initial_basic_delay_cap_seconds':5.0,'tactical_cover_distance':1.0,'tactical_cover_multiplier':0.7,'tactical_cover_ai':true,'normal_target_policies':[frozen.policies[left],frozen.policies[right]]})
  var teams:Array=[]
  if frozen.controllers[left]=='ai':teams.append(0)
  if frozen.controllers[right]=='ai':teams.append(1)
  settings['tactical_ai_teams']=teams
  if teams.size()==2:
   var job=Offscreen.new();var error:String=job.configure(frozen.armies[left],frozen.armies[right],left,right,settings.seed,settings,frozen.arena)
   if not error.is_empty():return _fail(error)
   ai_jobs.append(job)
  else:
   var duel=Duel.new();var id:String='r'+str(frozen.round)+'-d'+str(index)
   var result:Dictionary=duel.configure({'id':id,'left_id':left,'right_id':right,'generation':int(frozen.round)*10+index,'positions':[frozen.positions[left],frozen.positions[right]]},[frozen.armies[left],frozen.armies[right]],frozen.arena,settings)
   if not result.ok:return _fail(result.error)
   duels[id]=duel;_participant_duel[left]=id;_participant_duel[right]=id
 return {'ok':true}
func mark_loaded(participant_id:String)->Dictionary:
 if rules._state.phase!='loading' or rules.controllers.get(participant_id)!='human':return {'ok':false,'error':'wrong_phase_or_owner'}
 _loaded[participant_id]=true
 for id in rules.controllers:
  if rules.controllers[id]=='human' and not _loaded.get(id,false):return {'ok':true,'waiting':true}
 rules.begin_battle()
 for duel in duels.values():duel.start()
 return {'ok':true,'started':true}
func advance(delta:float)->Array:
 if rules._state.get('phase')!='battle' or not last_error.is_empty():return []
 var batches:Array=[]
 for id in duels:
  var events:Array=duels[id].advance(delta)
  if not events.is_empty():batches.append({'battle_id':id,'events':events})
 for job in ai_jobs:
  if not job.is_complete():job.advance(64)
 var results:Array=[]
 for duel in duels.values():
  if duel.result().is_empty():return batches
  results.append(duel.result())
 for job in ai_jobs:
  if not job.is_complete():return batches
  results.append(job.result)
 var settled:Dictionary=rules.commit_duels(results)
 if not settled.ok:_fail(settled.error)
 return batches
func view_for(participant_id:String)->Dictionary:
 var view:Dictionary=rules.player_view(participant_id)
 if view.is_empty():return {}
 view['controller_epoch']=controller_epochs.get(participant_id,0)
 view['last_result']=rules._state.last_result.duplicate(true)
 if _participant_duel.has(participant_id):view['battle']=duels[_participant_duel[participant_id]].snapshot()
 return view
func events_since(participant_id:String,sequence:int)->Array:
 return duels[_participant_duel[participant_id]].events_since(sequence) if _participant_duel.has(participant_id) else []
func next_round()->Dictionary:
 var result:Dictionary=rules.advance_round()
 if result.ok:_participant_duel.clear()
 return result
func request_next(participant_id:String)->Dictionary:
 if rules._state.phase!='result' or rules.controllers.get(participant_id)!='human':return {'ok':false,'error':'wrong_phase_or_owner'}
 _continue[participant_id]=true
 for id in rules.controllers:
  if rules.controllers[id]=='human' and not _continue.get(id,false):return {'ok':true,'waiting':true}
 return next_round()
func close()->void:
 for duel in duels.values():duel.close()
 for job in ai_jobs:job.cancel()
 duels.clear();ai_jobs.clear();_participant_duel.clear();_loaded.clear()
func _fail(reason:String)->Dictionary:
 last_error=reason;return {'ok':false,'error':reason}

func take_over(participant_id:String)->Dictionary:
 if participant_id=='p0' or participant_id not in ['p1','p2']:return {'ok':false,'error':'invalid_takeover'}
 if rules.controllers.get(participant_id)=='ai':return {'ok':true}
 var result:Dictionary=rules.take_over(participant_id)
 if not result.ok:return result
 controller_epochs[participant_id]+=1
 if _participant_duel.has(participant_id):
  var duel=duels[_participant_duel[participant_id]]
  duel.clock.sim.enable_ai_team(0 if duel.pair.left_id==participant_id else 1)
 match rules._state.phase:
  'preparation':
   if rules.ready.values().all(func(value):return value):return begin_round()
  'loading':return mark_loaded('p0') if _loaded.get('p0',false) else {'ok':true}
  'result':return request_next('p0') if _continue.get('p0',false) else {'ok':true}
 return {'ok':true}
