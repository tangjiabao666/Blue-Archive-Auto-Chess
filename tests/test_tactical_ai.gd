extends SceneTree
const Sim=preload('res://core/tactical_sim.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func roster()->Array:return [{'id':10,'team':0,'cell':Vector2(0,2),'character_id':'serika','star':2},{'id':20,'team':1,'cell':Vector2(0,-2),'character_id':'serika','star':2}]
func _initialize()->void:
 var path:='res://core/tactical_ai.gd';ck(FileAccess.file_exists(path),'tactical AI exists')
 if failures:finish();return
 var ai=load(path).new();var s=Sim.new();s.configure(roster(),{'seed':17});s.start()
 ai.configure([1],7,{'serika':s.character_data('serika')},s.options.source_units_per_world_unit)
 var view:Dictionary=s.snapshot();view.erase('pending_hits');view.tactical.erase('queue')
 ck(ai.decide(view,9).is_empty(),'AI waits decision cadence')
 var commands:Array=ai.decide(view,10)
 ck(commands.size()==1,'one decision per controlled team')
 if commands.size()==1:
  ck(commands[0].team==1 and commands[0].actor_id==20 and commands[0].generation==7 and commands[0].tick==11,'decision has owned actor and future tick')
 ck(ai.decide(view,10).is_empty(),'repeat decision tick has no new command')
 view.tactical.resources.teams[1].energy=1
 ck(ai.decide(view,20).is_empty(),'AI cannot spend unaffordable energy')
 view.tactical.resources.teams[1].energy=10;view.units[1].star=1
 ck(ai.decide(view,30).is_empty(),'AI obeys star unlock')
 ai.configure([1],7,{'serika':s.character_data('serika')},s.options.source_units_per_world_unit)
 view=s.snapshot();view.tactical.erase('queue')
 view.telegraphs=[{'id':1,'source':10,'team':0,'ability':'ex','cast_start_tick':10,'shape':'line','origin':Vector2(0,2),'direction':Vector2.UP,'width':2.0,'length':10.0,'impacts':[{'due':100}]}]
 ck(ai.decide(view,20).all(func(c):return c.type!='move'),'AI does not instantly dodge a fresh warning')
 var before_view:Dictionary=view.duplicate(true)
 var dodge:Array=ai.decide(view,30)
 ck(dodge.size()==1 and dodge[0].type=='move' and dodge[0].point.distance_to(view.units[1].cell)<=4,'AI reacts to published geometry after bounded delay')
 ck(view==before_view,'AI does not mutate public snapshot')
 var controlled=Sim.new();controlled.set_command_generation(7)
 ck(controlled.configure(roster(),{'seed':17,'tactical_ai_teams':[1]}).is_empty(),'configure controlled enemy')
 if controlled.units.is_empty():finish();return
 for u in controlled.units:u.hp=1000000000;u.max_hp=1000000000
 controlled.start();var player_casts:=0;var enemy_casts:=0
 for i in range(60):
  for event in controlled.step():
   if event.type=='skill':
    if event.actor_id==10:player_casts+=1
    if event.actor_id==20:enemy_casts+=1
 ck(player_casts==0 and enemy_casts==1,'only enemy auto decision casts, CD respected')
 ck(controlled.snapshot().tactical.resources.teams[1].energy==3,'enemy pays same source cost and uses same regen')
 finish()
func finish()->void:
 print('TACTICAL_AI checks=',checks,' failures=',failures);quit(1 if failures else 0)
