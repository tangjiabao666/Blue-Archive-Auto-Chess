extends SceneTree
const Sim=preload('res://core/tactical_sim.gd')
const Legacy=preload('res://core/character_sim.gd')
const Hooks=preload('res://core/combat_arena_hooks.gd')
const Navigation=preload('res://core/obstacle_navigation.gd')
const LOW={'rect':Rect2(-1,-0.2,2,0.4),'blocks_projectiles':false}
const HIGH={'rect':Rect2(-1,-0.2,2,0.4),'blocks_projectiles':true}
var checks:=0
var failures:=0
var _hooks:Array=[]
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func make_sim(obstacles:Array,source_key:String='serika',target_key:String='serika',legacy:bool=false):
 var s=Legacy.new() if legacy else Sim.new()
 var nav=Navigation.new();var hooks=Hooks.new();_hooks.append(hooks)
 ck(nav.configure(6.6,obstacles).is_empty(),'configure cover navigation')
 hooks.bind(s,nav,obstacles)
 ck(s.configure([{'id':0,'team':0,'cell':Vector2(0,3),'character_id':source_key,'star':2},{'id':1,'team':1,'cell':Vector2(0,-0.65),'character_id':target_key,'star':1}],{'seed':17,'random_damage':false}).is_empty(),'configure source-backed cover combat')
 for u in s.units:u.hp=100000000;u.max_hp=100000000;u.busy_until=100000;u.basic_ready=100000;u.sub_ready=100000;u.skill_ready=100000
 s.start()
 return s
func release(s)->void:
 s.path_step=Callable();s.cover_query=Callable()
 if s.has_method('bind_tactical_cover'):s.bind_tactical_cover(Callable())
func hit_for(s,ratio:float=1.0,policy:String='direct')->Dictionary:
 return {'source':0,'target':1,'due':s.tick,'effect':'damage','atk_ratio':ratio,'can_crit':false,'kind':'attack','ability':'normal','component':'normal','hit_index':0,'hit_count':1,'origin':s.units[0].cell,'target_cell':s.units[1].cell,'contact_policy':policy}
func damage_events(s,hit:Dictionary)->Array:
 s.events=[];s._resolve_hit(hit)
 return s.events.filter(func(e):return e.type=='damage')
func expected(s,ratio:float,multiplier:float=1.0)->int:
 return int(floor(s.damage_components(s.units[0],s.units[1],ratio).raw*multiplier))
func _initialize()->void:
 test_direction_and_distance()
 test_current_contact_position()
 test_tactical_moves_before_contact()
 test_seeded_contact_parity()
 test_source_stats_shield_and_echo()
 test_high_cover_and_bypass()
 test_source_scheduling()
 test_secondary_fan_origin()
 test_legacy_unchanged()
 _hooks.clear()
 print('DIRECTIONAL_COVER checks=',checks,' failures=',failures)
 quit(1 if failures else 0)
func test_direction_and_distance()->void:
 var s=make_sim([LOW])
 var actor:Dictionary=s.units[0];var target:Dictionary=s.units[1]
 for scenario in [
  {'label':'front','source':Vector2(0,3),'target':Vector2(0,-0.65),'factor':0.8},
  {'label':'flank','source':Vector2(3,-0.65),'target':Vector2(0,-0.65),'factor':1.0},
  {'label':'back','source':Vector2(0,-3),'target':Vector2(0,-0.65),'factor':1.0},
  {'label':'beyond cover proximity','source':Vector2(0,3),'target':Vector2(0,-0.81),'factor':1.0},
  {'label':'proximity boundary','source':Vector2(0,3),'target':Vector2(0,-0.8),'factor':0.8},
  {'label':'opposite team direction','source':Vector2(0,-3),'target':Vector2(0,0.65),'factor':0.8},
  {'label':'diagonal across cover','source':Vector2(3,2),'target':Vector2(0,-0.65),'factor':0.8},
  {'label':'diagonal misses cover','source':Vector2(3,0.3),'target':Vector2(0,-0.65),'factor':1.0},
 ]:
  actor.cell=scenario.source;target.cell=scenario.target
  var events:Array=damage_events(s,hit_for(s))
  ck(events.size()==1 and events[0].raw_amount==expected(s,1.0,scenario.factor),scenario.label+' applies only incoming directional protection')
  ck(events.size()==1 and events[0].atk_ratio==1.0,scenario.label+' retains original source coefficient')
 ck(not target.in_cover,'directional reduction does not replace source in_cover state')
 release(s)
 var stacked=make_sim([{'rect':Rect2(-1,-0.05,2,0.05),'blocks_projectiles':false},{'rect':Rect2(-1,0.1,2,0.05),'blocks_projectiles':false}])
 stacked.units[1].cell=Vector2(0,-0.45)
 var events:Array=damage_events(stacked,hit_for(stacked))
 ck(events.size()==1 and events[0].raw_amount==expected(stacked,1.0,0.8),'multiple crossed low obstacles do not stack mitigation')
 release(stacked)
func test_current_contact_position()->void:
 var s=make_sim([LOW]);var target:Dictionary=s.units[1]
 var hit:Dictionary=hit_for(s)
 target.cell=Vector2(2,-0.65)
 var events:Array=damage_events(s,hit)
 ck(events.size()==1 and events[0].raw_amount==expected(s,1.0),'moving out before contact removes protection despite stored target_cell')
 hit=hit_for(s);target.cell=Vector2(0,-0.65)
 events=damage_events(s,hit)
 ck(events.size()==1 and events[0].raw_amount==expected(s,1.0,0.8),'moving into cover before contact gains protection despite stored target_cell')
 events=damage_events(s,hit)
 ck(events.size()==1 and events[0].raw_amount==expected(s,1.0,0.8),'reusing a pending contact does not compound or mutate reduction')
 ck(hit.atk_ratio==1.0,'contact reduction never mutates scheduled coefficients')
 release(s)
func test_tactical_moves_before_contact()->void:
 for moving_in in [false,true]:
  var s=make_sim([LOW]);var target:Dictionary=s.units[1]
  target.cell=Vector2(2,-0.65) if moving_in else Vector2(0,-0.65)
  var destination:=Vector2(0,-0.65) if moving_in else Vector2(2,-0.65)
  var hit:Dictionary=hit_for(s);hit.due=20;s._pending.append(hit)
  ck(s.queue_tactical_command({'generation':0,'team':1,'sequence':1,'tick':1,'type':'move','actor_id':1,'target_id':-1,'point':destination}).ok,'queue actual tactical movement before contact')
  var received:Array=[];var moves:=0
  for _i in range(20):
   for event in s.step():
    if event.type=='move' and event.get('tactical',false):moves+=1
    if event.type=='damage' and event.actor_id==0:received.append(event)
  ck(moves>0 and target.cell.is_equal_approx(destination),'tactical command reaches requested cover position')
  ck(received.size()==1 and received[0].raw_amount==expected(s,1.0,0.8 if moving_in else 1.0),'impact uses cover position after executed move '+str(moving_in))
  release(s)
func test_seeded_contact_parity()->void:
 var covered=make_sim([LOW]);var plain=make_sim([])
 covered.options.random_damage=true;plain.options.random_damage=true
 for _i in range(100):
  var a:Array=damage_events(covered,hit_for(covered));var b:Array=damage_events(plain,hit_for(plain))
  ck(a.size()==b.size(),'cover never changes seeded hit probability')
  if not a.is_empty():ck(a[0].critical==b[0].critical and a[0].atk_ratio==b[0].atk_ratio,'cover keeps seeded crit and source ratio')
 ck(covered._rng.state==plain._rng.state,'cover consumes no additional random draws')
 release(covered);release(plain)
func test_source_stats_shield_and_echo()->void:
 var s=make_sim([LOW],'serika','tsubaki')
 s._buff(s.units[0],'test_attack','AttackPower',0.35,100,'ex')
 s._buff(s.units[1],'test_defense','DefensePower',0.25,100,'ex')
 s.units[1].reload_until=100;s.units[1].shield=100
 var unmodified:Dictionary=s.damage_components(s.units[0],s.units[1],2.0)
 var raw:int=int(floor(unmodified.raw*0.8))
 var events:Array=damage_events(s,hit_for(s,2.0))
 ck(events.size()==1 and events[0].raw_amount==raw,'cover composes with source attack, defense and reload reduction before one final rounding')
 ck(events.size()==1 and events[0].absorbed==mini(100,raw) and events[0].amount==maxi(0,raw-100),'shield absorbs reduced authoritative damage')
 ck(s.damage_components(s.units[0],s.units[1],2.0)==unmodified,'damage context is restored after contact')
 release(s)
 var echo=make_sim([LOW],'hina')
 var echo_ratio:float=echo.character_data('hina').sub.echoAtkRatio
 events=damage_events(echo,hit_for(echo))
 ck(events.size()==2,'source Hina echo trigger is preserved')
 if events.size()==2:
  ck(events[0].raw_amount==expected(echo,1.0,0.8),'primary applies cover once')
  ck(events[1].component=='echo' and events[1].atk_ratio==echo_ratio and events[1].raw_amount==expected(echo,echo_ratio,0.8),'recursive source echo applies cover once with its own coefficient')
 release(echo)
func test_high_cover_and_bypass()->void:
 for obstacle in [LOW,HIGH]:
  var s=make_sim([obstacle])
  ck(s.line_of_sight.call(s.units[0].cell,s.units[1].cell)==not obstacle.blocks_projectiles,'high cover blocks LOS while low cover permits direct attacks')
  for policy in ['direct','lob','penetrating']:
   var events:Array=damage_events(s,hit_for(s,1.0,policy))
   if obstacle.blocks_projectiles and policy=='direct':ck(events.is_empty(),'direct contact cannot land through high cover')
   else:ck(events.size()==1 and events[0].raw_amount==expected(s,1.0,0.8 if policy=='direct' else 1.0),'policy '+policy+' observes the appropriate cover rule')
  release(s)
func test_source_scheduling()->void:
 var s=make_sim([LOW]);var actor:Dictionary=s.units[0]
 s._normal_attack(actor,s.units[1]);actor.busy_until=100000
 var pending:Array=s._pending.duplicate(true)
 var attack:Dictionary=s.character_data(actor.character_id).normalAttack
 ck(pending.size()==attack.hitWeights.size(),'native normal burst contact count stays intact')
 var expected_hits:Array=[]
 for index in range(pending.size()):
  var ratio:float=attack.totalAtkRatioPerBurst*attack.hitWeights[index]
  ck(is_equal_approx(pending[index].atk_ratio,ratio),'native normal burst weight retained '+str(index))
  expected_hits.append(expected(s,ratio,0.8))
 var received:Array=[]
 for _i in range(100):
  for event in s.step():
   if event.type=='damage' and event.actor_id==0 and event.ability=='normal':received.append(event.raw_amount)
  if s._pending.is_empty():break
 ck(received==expected_hits,'scheduled normal burst contacts each receive exactly one reduction')
 release(s)
 for source_key in ['hina','aris','mutsuki']:
  var a=make_sim([LOW],source_key)
  var b=make_sim([],source_key)
  ck(a._cast_source_skill(a.units[0],'ex') and b._cast_source_skill(b.units[0],'ex'),'source EX casts '+source_key)
  var volumes:Array=a.attack_telegraphs()
  ck(not volumes.is_empty(),'source EX builds actual spatial volumes '+source_key)
  var protected:Array=[];var plain:Array=[]
  for _i in range(180):
   for event in a.step():
    if event.type=='damage' and event.actor_id==0 and event.ability=='ex':protected.append(event)
   for event in b.step():
    if event.type=='damage' and event.actor_id==0 and event.ability=='ex':plain.append(event)
   if a.attack_telegraphs().is_empty() and a._pending.is_empty():break
  ck(not protected.is_empty() and protected.size()==plain.size(),'spatial contact schedule retained '+source_key)
  for index in range(mini(protected.size(),plain.size())):
   var factor:float=0.8 if source_key=='hina' else 1.0
   ck(protected[index].raw_amount==expected(a,protected[index].atk_ratio,factor),'spatial contact tagged cover policy '+source_key+' '+str(index))
   ck(protected[index].atk_ratio==plain[index].atk_ratio and protected[index].tick==plain[index].tick,'spatial source coefficient and schedule unchanged '+source_key+' '+str(index))
  release(a);release(b)
func test_secondary_fan_origin()->void:
 var s=make_sim([LOW],'iori')
 # A rear fan originates behind the cover: its secondary ray never crosses it.
 var volume:Dictionary={'source':0,'team':0,'ability':'ex','cast_start_tick':0,'origin':Vector2(0,3),'direction':Vector2.DOWN,'shape':'target_fan','fan_origin':Vector2(0,-0.65),'primary_target':99,'radius':5.0,'degrees':60.0,'contact_policy':'direct','impacts':[{'due':1,'hit':hit_for(s)}]}
 volume.impacts[0].hit.ability='ex';volume.impacts[0].hit.component='rear_fan'
 s.units[1].cell=Vector2(0,-0.75)
 s._publish_volume(volume)
 var events:Array=s.step().filter(func(e):return e.type=='damage')
 ck(events.size()==2 and events[0].raw_amount==expected(s,1.0),'secondary fan uses actual fan origin rather than original shooter across low cover')
 release(s)
func test_legacy_unchanged()->void:
 var old=make_sim([LOW],'serika','serika',true)
 var events:Array=damage_events(old,hit_for(old))
 ck(events.size()==1 and events[0].raw_amount==expected(old,1.0),'legacy source simulation does not gain tactical damage mitigation')
 ck(not old.cover_query.call(old.units[1]),'legacy low obstacle does not become in_cover')
 release(old)
