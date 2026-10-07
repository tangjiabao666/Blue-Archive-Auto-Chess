extends SceneTree
## CPU-only UI projection; optional -- --baseline=/absolute/path/baseline_strip.gd.
const Strip=preload("res://scripts/combat_status_strip.gd")
class CountingPresenter extends "res://core/combat_status_presenter.gd":
 var calls:int=0
 func present(unit:Dictionary,tick:int,definition:Dictionary,preparation:bool=false)->Dictionary:
  calls+=1;return super.present(unit,tick,definition,preparation)
func _initialize():call_deferred("run")
func run():
 var session=load("res://core/game_session.gd").new();var roster:Array=[]
 for team in 2:
  for i in 6:roster.append({"id":team*6+i,"team":team,"cell":Vector2(-4+1.6*i,3.8 if team==0 else -3.8),"character_id":session.ACTIVE[(i+team*7)%session.ACTIVE.size()],"star":2})
 assert(session.clock.sim.configure(roster,{"seed":771,"random_damage":false}).is_empty());session.clock.sim.start()
 var scripts:Dictionary={"current":Strip}
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--baseline="):scripts.baseline=load(arg.trim_prefix("--baseline="))
 var groups:Dictionary={}
 for key in scripts:
  var strips:Array=[]
  for unit in session.clock.sim.units:
   var strip=scripts[key].new();strip.presenter=CountingPresenter.new();root.add_child(strip);strips.append(strip)
  groups[key]={"strips":strips,"us":0}
 var definitions:Array=[]
 for unit in session.clock.sim.units:definitions.append(session.clock.sim.character_data(unit.character_id))
 var order:Array=groups.keys();var parity_checks:int=0
 for frame in 1800:
  session.clock.advance(1.0/60)
  if frame%60==0:order.reverse()
  for key in order:
   var group:Dictionary=groups[key];var begin:int=Time.get_ticks_usec()
   for i in roster.size():group.strips[i].update_unit(session.clock.sim.units[i],session.clock.sim.tick,definitions[i],false)
   group.us+=Time.get_ticks_usec()-begin
  if groups.has("baseline"):
   for i in roster.size():
    assert(groups.current.strips[i].status==groups.baseline.strips[i].status,"projection parity")
    assert(groups.current.strips[i].tooltip_text==groups.baseline.strips[i].tooltip_text,"tooltip parity")
    parity_checks+=2
 var results:Dictionary={"frames":1800,"units":12,"tick":session.clock.sim.tick,"parity_checks":parity_checks,"variants":{}}
 for key in groups:
  var group:Dictionary=groups[key];var calls:int=0
  for strip in group.strips:calls+=strip.presenter.calls;strip.free()
  results.variants[key]={"mean_ms":group.us/1800.0/1000,"projection_calls":calls}
 print("STATUS_CACHE_CPU ",JSON.stringify(results));quit()
