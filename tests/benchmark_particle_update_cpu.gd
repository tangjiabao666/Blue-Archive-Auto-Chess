extends SceneTree
## Paired deterministic 4v4 (default) or 6v6 CPU benchmark, never a rendered FPS claim.
## Pass -- --baseline /absolute/path/to/frozen_native_effect_player.gd [--team-size 6]
const Session=preload("res://core/game_session.gd")
const Stage=preload("res://scripts/battle_stage.gd")
const Player=preload("res://vfx/native_effect_player.gd")
var failed:=false
var team_size:=4
func _initialize()->void:call_deferred("run")
func fixture(script:GDScript)->Dictionary:
 var session=Session.new();var stage=Stage.new();root.add_child(stage);stage.configure(session.profiles,Session.OBSTACLES)
 stage.native_vfx._player.free();stage.native_vfx._player=script.new();stage.native_vfx.add_child(stage.native_vfx._player)
 stage.native_props._particles.free();stage.native_props._particles=script.new();stage.native_props.add_child(stage.native_props._particles)
 var roster:Array=[]
 for team in range(2):
  for i in range(team_size):roster.append({"id":team*7+i,"team":team,"cell":Vector2((i-(team_size-1)*0.5)*1.6,3.8 if team==0 else -3.8),"character_id":Session.ACTIVE[(i+team*team_size)%Session.ACTIVE.size()],"star":2})
 var error:String=session.clock.sim.configure(roster,{"seed":771,"random_damage":false,"initial_basic_delay_cap_seconds":Session.INITIAL_BASIC_DELAY_CAP_SECONDS})
 if not error.is_empty():printerr(error);failed=true
 session.clock.generation=1;session.clock.sim.start();stage.set_roster(session.clock.sim.units,1,false)
 return {"session":session,"stage":stage,"simulation_us":0,"presentation_us":0,"frames":0,"samples":[],"visible_samples":0,"scheduled_samples":0}
func sample(group:Dictionary)->void:
 var session=group.session;var stage=group.stage
 var before:=Time.get_ticks_usec()
 var events:Array=session.clock.advance(1.0/60.0)
 group.simulation_us+=Time.get_ticks_usec()-before
 var at:float=session.clock.sim.tick*0.05+session.clock.accumulator
 before=Time.get_ticks_usec();stage.update_display(session.clock.sim.units,events,at)
 var elapsed:int=Time.get_ticks_usec()-before
 group.presentation_us+=elapsed;group.samples.append(elapsed);group.frames+=1
 for player in [stage.native_vfx._player,stage.native_props._particles]:
  var d:Dictionary=player.diagnostics()
  group.visible_samples+=int(d.visible_particles);group.scheduled_samples+=int(d.scheduled_particles)
func run()->void:
 var args=OS.get_cmdline_user_args()
 for i in range(args.size()-1):
  if args[i]=="--team-size":team_size=clampi(int(args[i+1]),1,7)
 var candidates:Dictionary={"current":fixture(Player)}
 for i in range(args.size()-1):
  if args[i]=="--baseline":candidates.baseline=fixture(load(args[i+1]))
 var order:Array=candidates.keys()
 var comparisons:=0
 for frame in range(7200):
  if frame%60==0:order.reverse()
  for key in order:sample(candidates[key])
  if candidates.has("baseline") and frame%15==0:
   var a:Dictionary={"combat":candidates.current.stage.native_vfx.visual_snapshot(),"prop_particles":candidates.current.stage.native_props._particles.snapshot()}
   var b:Dictionary={"combat":candidates.baseline.stage.native_vfx.visual_snapshot(),"prop_particles":candidates.baseline.stage.native_props._particles.snapshot()}
   if var_to_bytes(a)!=var_to_bytes(b):printerr("FAIL: baseline VFX snapshot differs at frame ",frame);failed=true
   if candidates.current.session.clock.sim.snapshot()!=candidates.baseline.session.clock.sim.snapshot():
    printerr("FAIL: baseline simulation snapshot differs at frame ",frame);failed=true
   comparisons+=1
  if candidates.current.session.clock.sim.phase=="finished":break
 for key in candidates:
  var group:Dictionary=candidates[key]
  group.samples.sort()
  var d:Dictionary=group.stage.native_vfx._player.diagnostics()
  var prop_d:Dictionary=group.stage.native_props._particles.diagnostics()
  var measured_calls:int=int(d.get("shader_parameter_writes",0))+int(prop_d.get("shader_parameter_writes",0))
  var measured_states:int=int(d.get("particle_state_evaluations",0))+int(prop_d.get("particle_state_evaluations",0))
  var report:Dictionary={"variant":key,"actors":team_size*2,"frames":group.frames,"seed":771,"sim_tick":group.session.clock.sim.tick,"simulation_mean_ms":float(group.simulation_us)/group.frames/1000,"presentation_mean_ms":float(group.presentation_us)/group.frames/1000,"presentation_p95_ms":float(group.samples[int(group.samples.size()*0.95)])/1000,"visible_particle_samples":group.visible_samples,"scheduled_particle_samples":group.scheduled_samples,"shader_parameter_set_calls":measured_calls if d.has("shader_parameter_writes") else group.visible_samples*6,"shader_call_count_inferred":not d.has("shader_parameter_writes"),"particle_state_evaluations":measured_states if d.has("particle_state_evaluations") else -1,"snapshot_comparisons":comparisons,"parity_passed":not failed}
  print("PARTICLE_COMBAT_CPU ",JSON.stringify(report))
  group.stage.queue_free()
 await process_frame;quit(1 if failed else 0)
