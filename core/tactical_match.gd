extends "res://core/prototype_match.gd"
## Source economy with a separate six-round score ledger. Survival rules keep
## their own class; internal _state always retains the exact Rules6 shape.
const Health=preload('res://core/battle_outcome.gd')
var combat_max_ticks:int=3000
var hp_timeout:bool=false
const League=preload('res://core/tactical_league.gd')
var league=League.new()
var _pending_league
func new_match(seed_value:int=1,catalog:Array=[],config:Dictionary={})->Dictionary:
 var result:Dictionary=super.new_match(seed_value,catalog,config)
 if result.ok:league=_new_league();_pending_league=null
 return result
func snapshot()->Dictionary:
 var value:Dictionary=super.snapshot()
 if not value.is_empty():value.league=league.snapshot()
 return value
func execute(command:Variant)->Dictionary:
 var before:Dictionary=league.snapshot()
 var result:Dictionary=super.execute(command)
 if not result.ok:league.restore(before)
 _pending_league=null
 return result
func _prepare_ai(player:Dictionary)->void:
 # Six rounds need an explicit upgrade budget; no free XP or gold is added.
 var target:int=mini(int(_state.config.max_level),6 if int(_state.round)>=5 else 5 if int(_state.round)>=3 else 4)
 while player.level<target and player.gold>=_state.config.xp_cost:
  if not _buy_xp(player).ok:break
 var reserve:int=mini(4,int(player.gold)) if int(_state.round)==4 and player.level<mini(6,int(_state.config.max_level)) else 0
 player.gold-=reserve
 super._prepare_ai(player)
 player.gold+=reserve
 player.shop_locked=_has_unaffordable_third_copy(player)
func _damage_amount(_survivors:int,_round_number:int,_config:Dictionary)->int:return 0
func _resolve_battle(command:Dictionary)->Dictionary:
 if _state.get('phase')!='battle':return _failure('wrong_phase')
 if not command.get('league_outcomes') is Array:return _failure('missing_league_outcomes')
 if not command.get('ai_outcomes') is Array:return _failure('missing_ai_outcomes')
 var candidate=_new_league()
 if not candidate.restore(league.snapshot()).ok:return _failure('invalid_league_state')
 var recorded:Dictionary=candidate.record_round(int(_state.round),command.league_outcomes)
 if not recorded.ok:return _failure(recorded.error)
 if not _valid_combat_round(command.league_outcomes):return _failure('invalid_combat_history')
 var compared:Dictionary=command.duplicate(true);compared.opponent_id=_state.battle.opponent_id;compared.ai_results=command.ai_outcomes
 if not _matching_outcomes(command.league_outcomes,compared):return _failure('inconsistent_league_outcomes')
 _pending_league=candidate
 var result:Dictionary=super._resolve_battle(command)
 if result.ok:league=candidate
 _pending_league=null
 return result
func _complete_round(player:Dictionary,alive_ai:int)->void:
 if int(_state.round)<6:super._complete_round(player,alive_ai);return
 var table:Array=_pending_league.standings()
 var rank:int=table.filter(func(row):return row.participant_id=='p0')[0].rank
 _state.phase='finished';_state.next_opponent={};_state.outcome='victory' if rank==1 else 'defeat';_state.placement=rank
func _valid_finished_state(state:Dictionary,alive_ai:int)->bool:
 return int(state.round)==6 and alive_ai==7 and not state.players[0].eliminated and state.outcome in ['victory','defeat'] and _bounded(state.placement,1,8)
func _valid_snapshot(state:Dictionary,schema_version:int=VERSION)->bool:
 if not super._valid_snapshot(state,schema_version):return false
 if not _bounded(state.round,1,6):return false
 if int(state.next_battle_id)!=int(state.round)+(0 if state.phase=="preparation" else 1):return false
 for player in state.players:
  if player.hp!=state.config.starting_hp or player.eliminated:return false
 return true
func restore(candidate:Variant)->Dictionary:
 if not candidate is Dictionary or not candidate.has('league') or not _json_safe(candidate):return _failure('invalid_league_snapshot')
 var next_league=_new_league()
 if not candidate.league is Dictionary or not next_league.restore(candidate.league).ok:return _failure('invalid_league_snapshot')
 var core:Dictionary=_normalize_json(candidate);core.erase('league')
 if not _valid_snapshot(core):return _failure('invalid_snapshot')
 var rounds:Array=next_league.snapshot().rounds
 for saved_round in rounds:
  if not _valid_combat_round(saved_round.outcomes):return _failure("invalid_combat_history")
 var completed:int=int(core.round) if core.phase=='finished' else int(core.round)-1
 if rounds.size()!=completed:return _failure('inconsistent_league_round')
 if completed>0 and not _matching_outcomes(rounds.back().outcomes,core.last_result):return _failure('inconsistent_league_result')
 if core.phase=='finished':
  if not next_league.finished():return _failure('incomplete_league')
  var rank:int=next_league.standings().filter(func(row):return row.participant_id=='p0')[0].rank
  if core.placement!=rank or core.outcome!=('victory' if rank==1 else 'defeat'):return _failure('inconsistent_league_placement')
 var result:Dictionary=super.restore(core)
 if result.ok:league=next_league;_pending_league=null
 return result
func _valid_combat_round(rows:Array)->bool:
 if hp_timeout:return _new_league()._validate_outcomes(rows).ok
 var by_id:Dictionary={}
 for row in rows:by_id[row.participant_id]=row
 for row in rows:
  var ratio:float=float(row.remaining_hp_ratio)
  if row.result=='loss' and ratio!=0.0:return false
  if row.result=='win' and ratio<=0.0:return false
  if row.result=='draw' and ((ratio>0.0)!=(float(by_id[row.opponent_id].remaining_hp_ratio)>0.0)):return false
 return true
func _valid_ai_outcomes(outcomes:Variant,pairs:Array)->bool:
 if not super._valid_ai_outcomes(outcomes,pairs):return false
 for duel in outcomes:
  if duel.duration_ticks>combat_max_ticks or (duel.finish_reason=='timeout' and duel.duration_ticks!=combat_max_ticks):return false
 return true
func _valid_last_result(result:Dictionary,state:Dictionary)->bool:
 if not super._valid_last_result(result,state):return false
 if not result.eliminated_ids.is_empty():return false
 if state.phase=='finished':
  if not result.income_by_player.is_empty():return false
 elif result.income_by_player.size()!=8:return false
 for duel in result.ai_results:
  if duel.resolution!='simulation' or duel.finish_reason not in ['elimination','timeout','empty']:return false
  if duel.duration_ticks>combat_max_ticks or (duel.finish_reason=='timeout' and duel.duration_ticks!=combat_max_ticks):return false
 return true
func _matching_outcomes(rows:Array,result:Dictionary)->bool:
 var lookup:Dictionary={}
 for row in rows:
  if not row is Dictionary or not row.get('participant_id') is String:return false
  lookup[row.participant_id]=row
 if lookup.size()!=8 or not result.get('opponent_id') is String or not result.get('ai_results') is Array:return false
 if result.get('winner') not in ['player','opponent','draw']:return false
 if hp_timeout and (not result.get('combat') is Dictionary or not _health_rows_match(lookup.get('p0',{}),lookup.get(result.opponent_id,{}),result.combat)):return false
 var outcome:String='win' if result.winner=='player' else 'loss' if result.winner=='opponent' else 'draw'
 var opposite:String='loss' if outcome=='win' else 'win' if outcome=='loss' else 'draw'
 if not _row_matches(lookup.get('p0',{}),result.opponent_id,outcome,result.get('player_remaining')):return false
 if not _row_matches(lookup.get(result.opponent_id,{}),'p0',opposite,result.get('opponent_remaining')):return false
 for duel in result.ai_results:
  if not duel is Dictionary or duel.get('winner') not in ['left','right','draw']:return false
  if hp_timeout and not _health_rows_match(lookup.get(duel.get('left_id'),{}),lookup.get(duel.get('right_id'),{}),duel):return false
  var left:String='win' if duel.winner=='left' else 'loss' if duel.winner=='right' else 'draw'
  var right:String='loss' if left=='win' else 'win' if left=='loss' else 'draw'
  if not _row_matches(lookup.get(duel.get('left_id'),{}),str(duel.get('right_id')),left,duel.get('left_remaining')):return false
  if not _row_matches(lookup.get(duel.get('right_id'),{}),str(duel.get('left_id')),right,duel.get('right_remaining')):return false
 return true
func _row_matches(row:Dictionary,opponent:String,outcome:String,remaining:Variant)->bool:
 if row.is_empty() or row.get('opponent_id')!=opponent or row.get('result')!=outcome or not _whole(remaining):return false
 var ratio:Variant=row.get('remaining_hp_ratio')
 if not (ratio is int or ratio is float):return false
 return (float(ratio)>0.0)==(int(remaining)>0)

func _new_league():
 var value=League.new();value.hp_timeout=hp_timeout;return value
func _ai_outcome_keys()->Array:
 var keys:Array=super._ai_outcome_keys().duplicate()
 if hp_timeout:keys.append_array(Health.HEALTH_KEYS)
 return keys
func _ai_result_keys()->Array:
 var keys:Array=super._ai_result_keys().duplicate()
 if hp_timeout:keys.append_array(Health.HEALTH_KEYS)
 return keys
func _last_result_keys()->Array:
 var keys:Array=super._last_result_keys().duplicate()
 if hp_timeout:keys.append('combat')
 return keys
func _result_extension(command:Dictionary)->Dictionary:
 return {'combat':command.combat.duplicate(true)} if hp_timeout else {}
func _valid_player_outcome(value:Dictionary)->bool:
 if not hp_timeout:return super._valid_player_outcome(value)
 if not value.get('combat') is Dictionary or not _exact_keys(value.combat,['duration_ticks','finish_reason','remaining_hp_totals','maximum_hp_totals']):return false
 return Health.valid(Health.player_duel(value),6,6,combat_max_ticks)
func _valid_duel_outcome(duel:Dictionary,left_limit:int,right_limit:int,estimated:bool)->bool:
 if not hp_timeout:return super._valid_duel_outcome(duel,left_limit,right_limit,estimated)
 return not estimated and Health.valid(duel,left_limit,right_limit,combat_max_ticks)
func _health_rows_match(left:Dictionary,right:Dictionary,combat:Dictionary)->bool:
 if not combat.get('remaining_hp_totals') is Array or not combat.get('maximum_hp_totals') is Array:return false
 if combat.remaining_hp_totals.size()!=2 or combat.maximum_hp_totals.size()!=2:return false
 for side in range(2):
  var row:Dictionary=left if side==0 else right
  if row.get('remaining_hp_total')!=combat.remaining_hp_totals[side] or row.get('maximum_hp_total')!=combat.maximum_hp_totals[side]:return false
  if row.get('duration_ticks')!=combat.get('duration_ticks') or row.get('finish_reason')!=combat.get('finish_reason'):return false
 return true
