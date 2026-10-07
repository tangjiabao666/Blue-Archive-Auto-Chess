extends SceneTree
const Source=preload("res://vfx/native_source.gd")
const Player=preload("res://vfx/native_effect_player.gd")
func _initialize()->void:call_deferred("run")
func anchor(_binding:Dictionary,_event:Dictionary,_time:float)->Transform3D:return Transform3D.IDENTITY
func run()->void:
 var policy:Dictionary=Source.read_json("res://data/skill-impact-adaptations.json")
 for group in ["skills","normalMuzzleFallbacks"]:
  for key in policy[group]:
   var p:=Player.new();root.add_child(p)
   var path:String=policy[group][key].template
   var id:int=p.spawn(path,1,0.0,anchor)
   var particles:=0;var layers:=0;var end:=0.0
   for e in p.get("_effects"):
    end=maxf(end,e.end);layers+=e.layers.size()
    for layer in e.layers:particles+=layer.particles.size()
   p.update_time(0.0)
   print(JSON.stringify({"key":key,"template":path,"implemented_layers":layers,"scheduled_particles":particles,"seed1_duration_seconds":end,"at_contact_visible_particles":p.diagnostics().visible_particles,"issues":p.diagnostics().issues}))
   p.release(id);p.free()
 quit()
