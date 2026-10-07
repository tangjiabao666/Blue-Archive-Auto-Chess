extends RefCounted
## Rules-only fabricated evidence for save/terrain/profile tests. This helper
## never runs combat and must not be used to report measured battle outcomes.
static func command(game,battle:Dictionary,player_winner:String='draw',ai_winner:String='draw')->Dictionary:
 var hp_timeout:bool=game.rules_profile()==3
 var cap:int=1800 if hp_timeout else 3000
 var player:Dictionary=_duel('p0',battle.opponent_id,battle.player_units.size(),battle.opponent_units.size(),player_winner,cap,hp_timeout)
 var rows:Array=[];var ai:Array=[]
 _append(game,rows,player,hp_timeout)
 for pair in battle.ai_pairs:
  var duel:Dictionary=_duel(pair[0],pair[1],game.rules.get_player(pair[0]).deployed.size(),game.rules.get_player(pair[1]).deployed.size(),ai_winner,cap,hp_timeout)
  ai.append(duel);_append(game,rows,duel,hp_timeout)
 var result:Dictionary={'type':'resolve_battle','battle_id':battle.id,'winner':'player' if player.winner=='left' else 'opponent' if player.winner=='right' else 'draw','player_remaining':player.left_remaining,'opponent_remaining':player.right_remaining,'ai_outcomes':ai,'league_outcomes':rows}
 if hp_timeout:
  result.combat={'duration_ticks':player.duration_ticks,'finish_reason':player.finish_reason,'remaining_hp_totals':player.remaining_hp_totals.duplicate(),'maximum_hp_totals':player.maximum_hp_totals.duplicate()}
 return result
static func _duel(left:String,right:String,left_count:int,right_count:int,winner:String,cap:int,hp_timeout:bool)->Dictionary:
 # Test callers supply two nonempty armies. Unequal maxima deliberately prove
 # that equal total HP, rather than equal remaining ratios, is a timeout draw.
 assert(left_count>0 and right_count>0)
 var duel:Dictionary={'left_id':left,'right_id':right,'winner':winner,'left_remaining':left_count,'right_remaining':right_count,'duration_ticks':cap,'finish_reason':'timeout'}
 if hp_timeout:
  duel.remaining_hp_totals=[500,500] if winner=='draw' else [700,500] if winner=='left' else [500,1000]
  duel.maximum_hp_totals=[1000,2000]
 elif winner!='draw':
  duel.duration_ticks=300;duel.finish_reason='elimination'
  if winner=='left':duel.right_remaining=0
  else:duel.left_remaining=0
 return duel
static func _append(game,rows:Array,duel:Dictionary,hp_timeout:bool)->void:
 var ratios:Array
 if hp_timeout:ratios=[float(duel.remaining_hp_totals[0])/duel.maximum_hp_totals[0],float(duel.remaining_hp_totals[1])/duel.maximum_hp_totals[1]]
 else:ratios=[0.5 if duel.left_remaining>0 else 0.0,0.5 if duel.right_remaining>0 else 0.0]
 game._append_league_pair(rows,duel.left_id,duel.right_id,duel.winner,ratios,duel if hp_timeout else {})
