extends SceneTree
## CPU-only paired dense-Core benchmark; not rendering throughput.
## Optional baseline stage path: -- --baseline=/tmp/contact-boundary-baseline/battle_stage.gd
const Counter=preload("res://tests/fixtures/counting_event_pose_view.gd")
func _initialize():call_deferred("run")
func run():
 var session=load("res://core/game_session.gd").new()
 var source:String=FileAccess.get_file_as_string("res://scripts/battle_stage.gd")
 var measured:=GDScript.new()
 measured.source_code=source.replace('preload("res://scripts/unit_view.gd")','preload("res://tests/fixtures/counting_event_pose_view.gd")')
 assert(measured.reload()==OK)
 var candidates:Dictionary={"current":{"stage":measured.new(),"us":0,"frames":0}}
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--baseline="):
   candidates.baseline={"stage":load(arg.trim_prefix("--baseline=")).new(),"us":0,"frames":0}
 var roster:Array=[]
 for team in 2:
  for i in 6:roster.append({"id":team*6+i,"team":team,"cell":Vector2(-4.0+1.6*i,3.8 if team==0 else -3.8),"character_id":session.ACTIVE[i],"star":2})
 assert(session.clock.sim.configure(roster,{"seed":771,"random_damage":false}).is_empty())
 session.clock.sim.start();session.clock.generation=1
 for group in candidates.values():
  root.add_child(group.stage);group.stage.configure(session.profiles,session.OBSTACLES);group.stage.set_roster(session.clock.sim.units,1,false)
 Counter.event_advances=0;Counter.frame_advances=0;Counter.event_advance_us=0
 var event_types:Dictionary={}
 var order:Array=candidates.keys()
 var expected_event_advances:int=0
 for frame in 300:
  var events:Array=session.clock.advance(.08)
  for event in events:
   event_types[event.type]=int(event_types.get(event.type,0))+1
   var ids:Array=[]
   for id in [event.get("actor_id",-1),event.get("target_id",-1)]:
    if candidates.current.stage.views.has(id) and not ids.has(id):ids.append(id)
   expected_event_advances+=ids.size()*2
  if frame%30==0:order.reverse()
  for key in order:
   var group:Dictionary=candidates[key]
   var before:int=Time.get_ticks_usec()
   group.stage.update_display(session.clock.sim.units,events,session.clock.sim.tick*.05+session.clock.accumulator,session.clock.sim.tick)
   group.us+=Time.get_ticks_usec()-before;group.frames+=1
  if session.clock.sim.phase=="finished":break
 var result:Dictionary={"actors":12,"tick":session.clock.sim.tick,"event_counts":event_types,"event_advances":Counter.event_advances,"expected_event_advances":expected_event_advances,"frame_advances":Counter.frame_advances,"event_advance_total_ms":Counter.event_advance_us/1000.0,"variants":{}}
 for key in candidates:
  var group:Dictionary=candidates[key]
  result.variants[key]={"frames":group.frames,"presentation_mean_ms":float(group.us)/group.frames/1000.0}
  group.stage.free()
 print("CONTACT_BOUNDARY_CPU ",JSON.stringify(result));quit()
