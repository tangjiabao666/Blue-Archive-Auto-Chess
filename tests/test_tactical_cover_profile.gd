extends SceneTree
const Sim=preload('res://core/tactical_sim.gd')
const Hooks=preload('res://core/combat_arena_hooks.gd')
const Navigation=preload('res://core/obstacle_navigation.gd')
const LOW={'rect':Rect2(-1,-0.2,2,0.4),'blocks_projectiles':false}
const PROFILE={'tactical_cover_distance':1.0,'tactical_cover_multiplier':0.7,'tactical_cover_ai':true}
var checks:=0
var failures:=0
var owned_hooks:Array=[]
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func roster(star:int=1)->Array:
 return [{'id':0,'team':0,'cell':Vector2(0,3),'character_id':'serika','star':1},{'id':1,'team':1,'cell':Vector2(2,-1),'character_id':'serika','star':star}]
func make(settings:Dictionary=PROFILE,obstacles:Array=[LOW],star:int=1):
 var s=Sim.new();var nav=Navigation.new();var hooks=Hooks.new();owned_hooks.append(hooks)
 ck(nav.configure(6.6,obstacles).is_empty(),'navigation accepts fixture')
 hooks.bind(s,nav,obstacles)
 var opts:Dictionary=settings.duplicate(true);opts.seed=17;opts.random_damage=false
 var error:String=s.configure(roster(star),opts)
 ck(error.is_empty(),'profile settings configure: '+error)
 if not error.is_empty():release(s);return null
 for u in s.units:u.basic_ready=100000;u.sub_ready=100000
 return s
func release(s)->void:
 s.path_step=Callable();s.cover_query=Callable();s.bind_tactical_cover(Callable())
func hit(s,policy:String='direct')->Dictionary:
 return {'source':0,'target':1,'due':s.tick,'effect':'damage','atk_ratio':1.0,'can_crit':false,'kind':'attack','ability':'normal','component':'normal','hit_index':0,'hit_count':1,'origin':s.units[0].cell,'target_cell':s.units[1].cell,'contact_policy':policy}
func contact(s,policy:String='direct')->int:
 s.events=[];s._resolve_hit(hit(s,policy));var values:Array=s.events.filter(func(e):return e.type=='damage')
 return values[0].raw_amount if not values.is_empty() else -1
func _initialize()->void:
 test_profile_geometry_status()
 test_atomic_settings_and_defaults()
 test_ai_legal_move_and_reserve()
 test_ai_priorities_and_reset()
 test_dodge_and_default_ai()
 test_profile_move_contact()
 test_candidate_nearest_threat()
 test_route_and_occupancy_guards()
 test_unreachable_no_charge_loss()
 test_measured_front_flank()
 owned_hooks.clear()
 print('TACTICAL_COVER_PROFILE checks=',checks,' failures=',failures)
 quit(1 if failures else 0)
func test_profile_geometry_status()->void:
 var s=make()
 if s==null:return
 s.units[1].hp=10000000;s.units[1].max_hp=10000000
 var raw:float=s.damage_components(s.units[0],s.units[1],1.0).raw
 for row in [
  ['near edge',Vector2(0,3),Vector2(0,-0.55),0.7,'protected'],
  ['expanded band',Vector2(0,3),Vector2(0,-1.1),0.7,'protected'],
  ['outer boundary',Vector2(0,3),Vector2(0,-1.2),0.7,'protected'],
  ['outside band',Vector2(0,3),Vector2(0,-1.21),1.0,'none'],
  ['flank',Vector2(3,-1.1),Vector2(0,-1.1),1.0,'exposed'],
  ['back',Vector2(0,-3),Vector2(0,-1.1),1.0,'exposed']]:
  s.units[0].cell=row[1];s.units[1].cell=row[2]
  ck(contact(s)==int(floor(raw*row[3])),row[0]+' correct direct damage')
  var status:Dictionary=s.snapshot().units[1].get('cover_status',{})
  ck(status.get('state','missing')==row[4],row[0]+' current public state')
  if row[4]!='none':
   ck(status.get('threat_id',-1)==0 and status.get('direction',Vector2.ZERO).is_equal_approx(s.units[1].cell.direction_to(s.units[0].cell)),row[0]+' nearest threat and direction')
   ck(is_equal_approx(status.get('multiplier',0.0),row[3]),row[0]+' public multiplier')
 s.units[0].cell=Vector2(0,3);s.units[1].cell=Vector2(0,-1.1)
 for policy in ['lob','penetrating']:ck(contact(s,policy)==int(floor(raw)),policy+' bypasses protection')
 ck(not s.units[1].in_cover,'directional status never claims native cover passive')
 s.units[0].hp=0
 ck(s.snapshot().units[1].get('cover_status',{}).get('state','missing')=='none','dead threat does not imply protection')
 release(s)
func test_atomic_settings_and_defaults()->void:
 var s=make({})
 if s==null:return
 s.units[1].cell=Vector2(0,-0.8)
 var raw:float=s.damage_components(s.units[0],s.units[1],1.0).raw
 ck(contact(s)==int(floor(raw*0.8)),'old profile retains 80 percent hit at 0.6 distance')
 s.units[1].cell=Vector2(0,-1.1)
 ck(contact(s)==int(floor(raw)),'old profile retains narrow band')
 var before:Dictionary=s.snapshot()
 for setting in [{'tactical_cover_distance':NAN},{'tactical_cover_distance':0.34},{'tactical_cover_distance':2.1},{'tactical_cover_distance':true},{'tactical_cover_multiplier':0.0},{'tactical_cover_multiplier':1.1},{'tactical_cover_multiplier':true},{'tactical_cover_ai':1}]:
  ck(not s.configure(roster(),setting).is_empty() and s.snapshot()==before,'invalid cover option rejects atomically '+str(setting))
 release(s)
func test_ai_legal_move_and_reserve()->void:
 var settings:Dictionary=PROFILE.duplicate();settings.tactical_ai_teams=[1]
 var s=make(settings)
 if s==null:return
 s.units[0].busy_until=100000;s.units[1].busy_until=100000;s.start()
 var selected:Array=[];var rejected:Array=[]
 for i in range(100):
  for event in s.step():
   if event.type=='tactical_move_started':selected.append(event)
   if event.type=='command_rejected':rejected.append(event)
 ck(selected.size()==1,'enemy actually selects one cover move without oscillation')
 if not selected.is_empty():ck(selected[0].actor_id==1 and selected[0].distance<=4.0,'enemy path and ownership meet normal command rules')
 var state:Dictionary=s.snapshot()
 ck(state.units[1].get('cover_status',{}).get('state','')=='protected','enemy arrives at protected firing position')
 ck(s.units[1].cell.distance_to(s.units[0].cell)<=s.units[1].range and s.line_of_sight.call(s.units[1].cell,s.units[0].cell),'selected protection still permits firing')
 ck(state.tactical.resources.teams[1].moves==1 and state.tactical.resources.teams[0].moves==2,'one emergency charge reserved and human charges untouched')
 ck(rejected.is_empty(),'validated cover plans create no invalid command spam')
 release(s)
func test_ai_priorities_and_reset()->void:
 var settings:Dictionary=PROFILE.duplicate();settings.tactical_ai_teams=[1]
 var s=make(settings,[LOW],2)
 if s==null:return
 s.units[0].busy_until=100000;s.start()
 var events:Array=[]
 for i in range(11):events.append_array(s.step())
 ck(events.any(func(e):return e.type=='skill' and e.actor_id==1),'affordable EX keeps priority over seeking cover')
 ck(not events.any(func(e):return e.type=='tactical_move_started'),'cover never preempts selected EX')
 var view:Dictionary=s._ai_view();view.tactical.resources.teams[1].energy=0;view.units[1].stun_until=100
 ck(s._ai.decide(view,20).is_empty(),'stun blocks cover decision')
 view.units[1].stun_until=0;view.tactical.ex_busy_until[1]=100
 ck(s._ai.decide(view,30).is_empty(),'active EX blocks cover decision')
 s.reset();s.set_command_generation(9)
 s.units[0].busy_until=100000;s.units[1].star=1;s.units[1].busy_until=100000;s.start()
 events=[]
 for i in range(11):events.append_array(s.step())
 ck(events.any(func(e):return e.type=='tactical_move_started'),'generation/reset clears cover search cooldown')
 ck(s.snapshot().tactical.queue.generation==9,'cover commands carry new generation')
 release(s)
func test_unreachable_no_charge_loss()->void:
 var settings:Dictionary=PROFILE.duplicate();settings.tactical_ai_teams=[1]
 for obstacles in [[],[{'rect':Rect2(-1,-0.2,2,0.4),'blocks_projectiles':true}],[LOW,{'rect':Rect2(1.1,-2,0.5,4),'blocks_projectiles':true}]]:
  var s=make(settings,obstacles)
  if s==null:continue
  # Short firing range deliberately rules out all protected firing positions.
  s.units[1].range=0.2
  for u in s.units:u.busy_until=100000
  s.start();var rejected:=0
  for i in range(70):
   for event in s.step():
    if event.type=='command_rejected':rejected+=1
  ck(s.snapshot().tactical.resources.teams[1].moves==2 and rejected==0,'no viable cover produces no spend or repeated rejected commands')
  release(s)
func test_measured_front_flank()->void:
 var rows:Array=[]
 for front in [true,false]:
  var settings:Dictionary=PROFILE.duplicate();settings.tactical_cover_ai=false
  var s=make(settings)
  if s==null:return
  s.units[1].cell=Vector2(0,-1.1)
  s.units[0].cell=Vector2(0,2.9) if front else Vector2(4,-1.1)
  s.units[1].busy_until=100000;s.units[1].basic_ready=100000;s.units[1].sub_ready=100000
  s.start();var total:=0;var hits:=0;var first_damage:=0
  for i in range(2000):
   for event in s.step():
    if event.type=='damage' and event.actor_id==0:
     total+=event.raw_amount;hits+=1
     if first_damage==0:first_damage=event.raw_amount
   if s.units[1].hp<=0:break
  rows.append({'case':'front' if front else 'flank','first_hit':first_damage,'hits':hits,'raw_damage':total,'ttk_ticks':s.tick,'dead':s.units[1].hp<=0})
  release(s)
 ck(rows[0].dead and rows[1].dead,'same-lineup fixed-distance native normal attacks reach terminal target death')
 ck(rows[0].first_hit<rows[1].first_hit and rows[0].ttk_ticks>rows[1].ttk_ticks,'front reduction measurably increases native normal-attack TTK')
 print('COVER_FRONT_FLANK_EVIDENCE ',JSON.stringify(rows))

func test_candidate_nearest_threat()->void:
 var s=make()
 if s==null:return
 s.units.append(s.preview_unit('serika',1,2,0,Vector2(-3,-1)))
 var view:Dictionary=s._ai_view()
 var before:Dictionary=view.duplicate(true)
 var selected:Dictionary=s._cover_planner.choose(s.units[1],view,10)
 ck(not selected.is_empty(),'multiple-threat fixture offers usable low cover')
 if not selected.is_empty():
  s.units[1].cell=selected.point
  ck(s.snapshot().units[1].cover_status.state=='protected','candidate protects from nearest threat at destination, not obsolete nearest at origin')
 ck(view==before,'planner never mutates its public input snapshot')
 release(s)
func test_route_and_occupancy_guards()->void:
 var s=make(PROFILE,[LOW,{'rect':Rect2(1.1,-3,0.5,6),'blocks_projectiles':true}])
 if s==null:return
 ck(s._cover_planner.choose(s.units[1],s._ai_view(),10).is_empty(),'Euclidean-near cover across long detour rejected by actual max4 route')
 ck(s.snapshot().tactical.resources.teams[1].moves==2,'route preflight never charges movement')
 release(s)
 s=make()
 if s==null:return
 var first:Dictionary=s._cover_planner.choose(s.units[1],s._ai_view(),10)
 ck(not first.is_empty(),'clear candidate available before occupancy change')
 if not first.is_empty():
  s.units.append(s.preview_unit('serika',1,2,1,first.point))
  var alternative:Dictionary=s._cover_planner.choose(s.units[1],s._ai_view(),10)
  ck(alternative.is_empty() or alternative.point.distance_to(first.point)>=0.7-0.000001,'occupied candidate never selected or charged')
 ck(s.snapshot().tactical.resources.teams[1].moves==2,'occupancy preflight never consumes move charge')
 release(s)

func test_dodge_and_default_ai()->void:
 var settings:Dictionary=PROFILE.duplicate();settings.tactical_ai_teams=[1]
 var s=make(settings)
 if s==null:return
 var view:Dictionary=s._ai_view()
 view.tactical.resources.teams[1].moves=1
 ck(s._ai.decide(view,10).is_empty(),'last emergency charge never used for cover')
 view.telegraphs=[{'id':1,'source':0,'team':0,'ability':'ex','cast_start_tick':0,'shape':'circle','centers':[s.units[1].cell],'origin':s.units[0].cell,'direction':Vector2.DOWN,'radius':1.0,'impacts':[{'due':50}]}]
 var decisions:Array=s._ai.decide(view,20)
 ck(decisions.size()==1 and decisions[0].type=='move' and decisions[0].point.distance_to(s.units[1].cell)>2.0,'telegraphed danger may spend reserved charge and outranks cover')
 release(s)
 s=make({'tactical_ai_teams':[1]})
 if s==null:return
 for u in s.units:u.busy_until=100000
 s.start();var orders:=0
 for i in range(40):
  for event in s.step():
   if event.type=='tactical_move_started':orders+=1
 ck(orders==0 and s.snapshot().tactical.resources.teams[1].moves==2,'default AI profile never seeks or spends on cover')
 release(s)
func test_profile_move_contact()->void:
 for entering in [true,false]:
  var settings:Dictionary=PROFILE.duplicate();settings.tactical_cover_ai=false
  var s=make(settings)
  if s==null:return
  s.units[1].cell=Vector2(2,-1.1) if entering else Vector2(0,-1.1)
  for u in s.units:u.busy_until=100000;u.hp=10000000;u.max_hp=10000000
  s.start()
  var raw:float=s.damage_components(s.units[0],s.units[1],1.0).raw
  var pending:Dictionary=hit(s);pending.due=20;s._pending.append(pending)
  var destination:=Vector2(0,-1.1) if entering else Vector2(2,-1.1)
  ck(s.queue_tactical_command({'generation':0,'team':1,'sequence':0,'tick':1,'type':'move','actor_id':1,'target_id':-1,'point':destination}).ok,'actual profile2 entry/exit command queues')
  var damage:Array=[]
  for i in range(20):
   for event in s.step():
    if event.type=='damage' and event.actor_id==0:damage.append(event.raw_amount)
  ck(s.units[1].cell.is_equal_approx(destination),'actual move reaches expanded cover band or exposed flank')
  ck(damage==[int(floor(raw*(0.7 if entering else 1.0)))],'contact uses current position after actual expanded-cover move')
  ck(s.units[1].cover_status.state==('protected' if entering else 'none'),'public status tracks completed movement immediately')
  release(s)
