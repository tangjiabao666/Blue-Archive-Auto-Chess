extends SceneTree
## Deterministic headless balance sample. CPU timings are NOT rendering FPS.
const Session=preload('res://core/game_session.gd')
const Sim=preload('res://core/tactical_sim.gd')
const Maps=preload('res://core/tactical_maps.gd')
const Navigation=preload('res://core/obstacle_navigation.gd')
const Hooks=preload('res://core/combat_arena_hooks.gd')
const LEFT=['hoshino','shiroko','serika','mutsuki','koharu','aris']
const RIGHT=['yuuka','iori','hina','haruna','tsubaki','nonomi']
func _initialize()->void:
 var session=Session.new();session.new_game(1,'tactical_v1')
 var samples:Array=[]
 for seed_value in range(1,21):
  var count:int=4 if seed_value<=10 else 6
  var map:Dictionary=Maps.new().get_map(Maps.MAP_IDS[(seed_value-1)%3])
  var nav=Navigation.new();assert(nav.configure(map.half_size,map.obstacles).is_empty())
  var sim=Sim.new();var hooks=Hooks.new();hooks.bind(sim,nav,map.obstacles)
  var roster:Array=[]
  for team in range(2):
   for index in range(count):
    var keys:Array=LEFT if team==0 else RIGHT
    roster.append({'id':team*7+index,'team':team,'character_id':keys[index],'star':2 if count==6 or index==(seed_value%count) else 1,'cell':map.deployment_points[team][index]})
  var options:Dictionary=session._battle_options(seed_value,'p1','p2');options.arena_half=map.half_size;options.tactical_ai_teams=[0,1]
  assert(sim.configure(roster,options).is_empty());sim.set_command_generation(1);sim.start()
  var ex_counts:Array=[0,0];var move_counts:Array=[0,0];var first_death:=-1;var finish_reason:='';var cpu_start:int=Time.get_ticks_usec()
  while sim.phase=='running':
   for event in sim.step():
    if event.type=='skill':ex_counts[sim._unit(event.actor_id).team]+=1
    elif event.type=='tactical_move_started':move_counts[sim._unit(event.actor_id).team]+=1
    elif event.type=='death' and first_death<0:first_death=sim.tick
    elif event.type=='finished':finish_reason=event.reason
  var row:Dictionary={'seed':seed_value,'actors_per_team':count,'map_id':map.id,'seconds':sim.tick*0.05,'first_death_seconds':first_death*0.05,'winner':sim.winner,'finish_reason':finish_reason,'ex_casts':ex_counts,'tactical_moves':move_counts,'remaining_hp_ratios':session._hp_ratios(sim.units),'cpu_ms':(Time.get_ticks_usec()-cpu_start)/1000.0,'roster':roster,'options':options}
  samples.append(row);print('BALANCE_SAMPLE ',JSON.stringify(row))
  sim.path_step=Callable();sim.cover_query=Callable();sim.bind_tactical_cover(Callable())
 var durations:Array=samples.map(func(row):return row.seconds);durations.sort()
 var report:Dictionary={'scope':'20 deterministic headless source-combat samples, public-information AI controls both teams under identical energy/CD/order rules; not human play or graphics FPS','engine':Engine.get_version_info().string,'samples':samples,'median_seconds':(durations[9]+durations[10])*0.5,'min_seconds':durations.front(),'max_seconds':durations.back(),'target_90_to_150_count':samples.filter(func(row):return row.seconds>=90 and row.seconds<=150).size(),'timeouts':samples.filter(func(row):return row.finish_reason=='timeout').size()}
 DirAccess.make_dir_recursive_absolute('res://evidence/tactical-balance')
 var output:String='tuned012' if '--tuned012' in OS.get_cmdline_user_args() else 'tuned' if '--tuned' in OS.get_cmdline_user_args() else 'baseline'
 var file=FileAccess.open('res://evidence/tactical-balance/'+output+'.json',FileAccess.WRITE);file.store_string(JSON.stringify(report,'  '));file.close()
 print('BALANCE_SUMMARY ',JSON.stringify({'median':report.median_seconds,'range':[report.min_seconds,report.max_seconds],'within_target':report.target_90_to_150_count,'timeouts':report.timeouts}));quit()
