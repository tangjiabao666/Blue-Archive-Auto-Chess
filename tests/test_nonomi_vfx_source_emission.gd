extends SceneTree
const Player=preload("res://vfx/native_effect_player.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func anchor(_binding:Dictionary,_event:Dictionary,_time:float)->Transform3D:return Transform3D.IDENTITY
func run()->void:
 var p:=Player.new();root.add_child(p)
 var handle:int=p.spawn("res://data/effects/nonomi/visual-templates.json#FX_Nonomi_Original_Ex01_Hit_Start",1,0.0,anchor)
 var core_particles:=0;var child_particles:=0
 for e in p.get("_effects"):
  for layer in e.layers:
   if layer.path=="FX_Nonomi_Original_Ex01_Hit_Start/Core":core_particles+=layer.particles.size()
   if layer.path=="FX_Nonomi_Original_Ex01_Hit_Start/Core/Muzzle_Line":child_particles+=layer.particles.size()
 ck(core_particles>0,"disabled stale SubModule back-reference cannot suppress Nonomi Core's enabled emission")
 ck(child_particles==0,"actually enabled unsupported child subemitter remains skipped")
 p.release(handle);p.free()
 print("NONOMI_VFX_SOURCE_EMISSION ",checks," checks; ",failures," failures");quit(1 if failures else 0)
