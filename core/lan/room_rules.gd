extends 'res://core/tactical_match.gd'
const Session=preload('res://core/game_session.gd')
const Maps=preload('res://core/tactical_maps.gd')
const Navigation=preload('res://core/obstacle_navigation.gd')
const Formation=preload('res://core/opponent_formations.gd')
const SCHEMAS={'buy_offer':['type','slot'],'sell_unit':['type','unit_id'],'deploy_unit':['type','unit_id'],'bench_unit':['type','unit_id'],'refresh_shop':['type'],'buy_xp':['type'],'set_shop_locked':['type','locked'],'claim_reinforcement':['type','round','slot'],'skip_reinforcement':['type','round'],'place_unit':['type','unit_id','point'],'deploy_at':['type','unit_id','point'],'set_normal_target_policy':['type','policy']}
var controllers:Dictionary={}
var ready:Dictionary={}
var positions:Dictionary={}
var normal_policies:Dictionary={}
var _prepared_ai:Dictionary={}
var _revision:=0
var _pairs:Array=[]
var _arena:Dictionary={}
var _navigation=Navigation.new()
var _source=Session.new()
func new_match(seed_value:int=1,human_ids:Array=['p0','p1','p2'],_unused:Dictionary={})->Dictionary:
 if not _bounded(seed_value,0,2147483646) or human_ids!=['p0','p1','p2']:return _failure('invalid_room_setup')
 hp_timeout=true;combat_max_ticks=1800;controllers.clear();positions.clear();normal_policies.clear();_prepared_ai.clear();_revision=0
 for i in range(8):
  var id:String='p'+str(i);controllers[id]='human' if id in human_ids else 'ai';normal_policies[id]='nearest';positions[id]={}
 return super.new_match(seed_value,_source.catalog,{'max_level':5,'level_shop_odds':1,'reinforcement_recruitment':1})
func snapshot()->Dictionary:
 var value:Dictionary=super.snapshot()
 value['controllers']=controllers.duplicate(true);value['ready']=ready.duplicate(true);value['positions']=positions.duplicate(true);value['revision']=_revision;value['pairs']=_pairs.duplicate(true)
 return value
func _prepare_ai(player:Dictionary)->void:
 if controllers.get(player.id)!='ai' or _prepared_ai.get(player.id)==_state.round:return
 super._prepare_ai(player);_prepared_ai[player.id]=_state.round
func _prepare_round()->void:
 _arena=Maps.new().get_map(Maps.MAP_IDS[posmod(int(_state.initial_seed)+int(_state.round)-1,3)])
 _navigation.configure(_arena.half_size,_arena.obstacles)
 super._prepare_round()
 _pairs=[['p0',_state.next_opponent.opponent_id]]+_state.next_opponent.ai_pairs.duplicate(true)
 ready.clear()
 for player in _state.players:
  ready[player.id]=controllers.get(player.id)=='ai'
  _sync_positions(player.id)
 _revision+=1
func execute_for(participant_id:String,command:Dictionary)->Dictionary:
 if not controllers.has(participant_id) or controllers[participant_id]!='human':return _failure('not_human_controller')
 if _state.get('phase')!='preparation':return _failure('wrong_phase')
 if ready.get(participant_id,false):return _failure('already_ready')
 var kind:Variant=command.get('type')
 if not kind is String or not SCHEMAS.has(kind) or not _exact_keys(command,SCHEMAS[kind]):return _failure('invalid_command')
 var player:Dictionary=_player_ref(participant_id)
 if kind=='set_normal_target_policy':
  if not command.policy is String or command.policy not in ['nearest','wounded']:return _failure('invalid_policy')
  normal_policies[participant_id]=command.policy;_revision+=1;return _success()
 if kind in ['place_unit','deploy_at']:
  if not command.unit_id is String or not command.point is Vector2 or not command.point.is_finite():return _failure('invalid_placement')
  if kind=='place_unit' and command.unit_id not in player.deployed:return _failure('unit_not_deployed')
  if kind=='deploy_at' and command.unit_id not in player.bench:return _failure('unit_not_on_bench')
  if not _valid_point(participant_id,command.unit_id,command.point):return _failure('invalid_placement')
  if kind=='deploy_at':
   var deployed:Dictionary=_apply_player_command(player,{'type':'deploy_unit','unit_id':command.unit_id})
   if not deployed.ok:return deployed
  positions[participant_id][command.unit_id]=command.point;_revision+=1;return _success()
 var before:Dictionary=_state.duplicate(true)
 var result:Dictionary=_apply_player_command(player,command)
 if not result.ok:_state=before;return result
 _sync_positions(participant_id);_revision+=1;return result
func set_ready(participant_id:String,value:bool)->Dictionary:
 if _state.get('phase')!='preparation' or controllers.get(participant_id)!='human':return _failure('wrong_phase_or_owner')
 var player:Dictionary=_player_ref(participant_id)
 if value:
  if player.deployed.is_empty():return _failure('empty_army')
  if player.reinforcement.get('status')=='pending':return _failure('reinforcement_pending')
  _sync_positions(participant_id)
  if positions[participant_id].size()!=player.deployed.size():return _failure('invalid_formation')
 ready[participant_id]=value;_revision+=1;return _success()
func freeze_round()->Dictionary:
 if _state.get('phase')!='preparation':return _failure('wrong_phase')
 for id in controllers:
  if not ready.get(id,false):return _failure('waiting_for_players')
 var armies:Dictionary={}
 for player in _state.players:armies[player.id]=_deployed_units(player)
 _state.phase='loading';_revision+=1
 return _success({'round':_state.round,'seed':_state.initial_seed,'pairs':_pairs,'armies':armies,'positions':positions,'arena':_arena,'controllers':controllers,'policies':normal_policies})
func player_view(participant_id:String)->Dictionary:
 if not controllers.has(participant_id):return {}
 var opponent:String=''
 for pair in _pairs:
  if participant_id in pair:opponent=pair[1] if pair[0]==participant_id else pair[0];break
 var rival:Dictionary=_player_ref(opponent)
 return {'phase':_state.phase,'round':_state.round,'revision':_revision,'participant_id':participant_id,'player':get_player(participant_id),'positions':positions.get(participant_id,{}).duplicate(true),'opponent_id':opponent,'opponent_army':_deployed_units(rival) if not rival.is_empty() else [],'opponent_positions':positions.get(opponent,{}).duplicate(true),'ready':ready.duplicate(true),'controllers':controllers.duplicate(true),'standings':league.standings(),'arena':_arena.duplicate(true),'config':_state.config.duplicate(true),'policy':normal_policies[participant_id]}
func _valid_point(participant_id:String,unit_id:String,point:Vector2)->bool:
 if point.y<0.35 or not _navigation.is_free(point,0.35):return false
 var player:Dictionary=_player_ref(participant_id)
 for other in player.deployed:
  if other!=unit_id and positions[participant_id].has(other) and point.distance_to(positions[participant_id][other])<0.7:return false
 return true
func _sync_positions(participant_id:String)->void:
 var player:Dictionary=_player_ref(participant_id)
 if not positions.has(participant_id):positions[participant_id]={}
 for unit_id in positions[participant_id].keys():
  if unit_id not in player.deployed:positions[participant_id].erase(unit_id)
 for unit_id in positions[participant_id].keys():
  if not _valid_point(participant_id,unit_id,positions[participant_id][unit_id]):positions[participant_id].erase(unit_id)
 var army:Array=_deployed_units(player);var definitions:Dictionary={}
 for unit in army:definitions[unit.character_id]=_source.clock.sim.character_data(unit.character_id)
 var formation=Formation.new();var suggested:Array=formation.positions(army,definitions,formation.style_for(participant_id),_navigation)
 for index in range(army.size()):
  var id:String=army[index].id
  if positions[participant_id].has(id):continue
  var candidates:Array=[-suggested[index]]
  for slot in range(11):candidates.append(Vector2(-7.5+slot*1.5,6.5))
  for point in candidates:
   if _valid_point(participant_id,id,point):positions[participant_id][id]=point;break

func commit_duels(results:Array)->Dictionary:
 if _state.phase!='battle' or results.size()!=4:return _failure('wrong_phase_or_results')
 var rows:Array=[];var seen:Dictionary={}
 for result in results:
  if not result is Dictionary or not result.get('ok',false) or not result.get('outcome') is Dictionary:return _failure('invalid_duel')
  var duel:Dictionary=result.outcome
  if not duel.get('left_id') is String or not duel.get('right_id') is String:return _failure('invalid_pair')
  var key:String=duel.left_id+':'+duel.right_id
  if seen.has(key) or [duel.left_id,duel.right_id] not in _pairs:return _failure('invalid_pair')
  seen[key]=true
  if not Health.valid(duel,_player_ref(duel.left_id).deployed.size(),_player_ref(duel.right_id).deployed.size(),1800):return _failure('invalid_health_outcome')
  var ratios:Array=Health.ratios(duel)
  for side in range(2):rows.append({'participant_id':duel.left_id if side==0 else duel.right_id,'opponent_id':duel.right_id if side==0 else duel.left_id,'result':'draw' if duel.winner=='draw' else 'win' if (duel.winner=='left')==(side==0) else 'loss','remaining_hp_ratio':ratios[side],'remaining_hp_total':duel.remaining_hp_totals[side],'maximum_hp_total':duel.maximum_hp_totals[side],'duration_ticks':duel.duration_ticks,'finish_reason':duel.finish_reason})
 var recorded:Dictionary=league.record_round(int(_state.round),rows)
 if not recorded.ok:return recorded
 var incomes:Dictionary={}
 if _state.round<6:
  for player in _state.players:
   var income:int=int(_state.config.income)+mini(int(player.gold)/int(_state.config.interest_step),int(_state.config.interest_cap))
   player.gold+=income;incomes[player.id]=income;_grant_xp(player,_state.config.round_xp)
   if player.shop_locked:player.shop_locked=false
   else:_roll_shop(player)
 _state.last_result={'round':_state.round,'duels':results.duplicate(true),'income_by_player':incomes,'standings':league.standings()}
 _state.phase='finished' if _state.round==6 else 'result';_revision+=1
 return _success()
func begin_battle()->void:
 if _state.phase=='loading':_state.phase='battle';_revision+=1
func advance_round()->Dictionary:
 if _state.phase!='result':return _failure('wrong_phase')
 _state.round+=1;_state.phase='preparation';_prepare_round();return _success()

func take_over(participant_id:String)->Dictionary:
 if participant_id=='p0' or not controllers.has(participant_id):return _failure('invalid_takeover')
 if controllers[participant_id]=='ai':return _success()
 controllers[participant_id]='ai'
 if _state.phase=='preparation' and not ready.get(participant_id,false):
  _prepare_ai(_player_ref(participant_id));_sync_positions(participant_id);ready[participant_id]=true
 _revision+=1
 return _success()
