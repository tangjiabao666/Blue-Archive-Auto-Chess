extends SceneTree
const Player=preload("res://vfx/native_effect_player.gd")
const Particles=preload("res://vfx/native_particles.gd")
const TEMPLATE="res://data/effects/hoshino/visual-templates.json#FX_Hoshino_Original_Ex01_Motion_Mesh_Muzzle"
var checks:=0
var failures:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr(label)
func identity(_b:Dictionary,_e:Dictionary,_at:float)->Transform3D:return Transform3D.IDENTITY
func _initialize():call_deferred("run")
func check_colors(player,reduced:bool)->void:
 var smoke_count:=0;var other_count:=0
 for effect in player._effects:
  for layer in effect.layers:
   for item in layer.particles:
    var raw:Dictionary=Particles.state(layer.params,item.sample,0.26)
    if not raw.visible:continue
    var descriptor:Dictionary=item.material.get_meta("native_source_descriptor",{})
    var source:Dictionary=descriptor.get("source",{})
    var confirmed:bool=source.get("cab","")=="CAB-72cabf238b0d84de1615649a40b6b13f" and str(source.get("pathId",""))=="-4702360996300803376"
    ck(layer.is_smoke==confirmed,"classification targets verified opaque smoke material, not fire shader names")
    var expected:Color=raw.color
    if reduced and layer.is_smoke:expected.a*=0.55
    var actual:Color=item.material.get_shader_parameter("particle_color")
    ck(actual==expected,"only classified smoke alpha changes")
    if layer.is_smoke:smoke_count+=1
    else:other_count+=1
 ck(smoke_count>0 and other_count>0,"real fixture exercises smoke and non-smoke")
func run():
 var player=Player.new();root.add_child(player)
 ck(player.has_method("set_reduce_smoke"),"optional smoke setting exists")
 if not player.has_method("set_reduce_smoke"):player.free();finish();return
 var handle:int=player.spawn(TEMPLATE,942,0.0,identity,2.0);player.update_time(0.26)
 var original:Dictionary=player.snapshot();check_colors(player,false)
 player.set_reduce_smoke(true);check_colors(player,true)
 ck(player.diagnostics().time==0.26,"changing option does not advance clock")
 var writes:int=player.diagnostics().shader_parameter_writes;player.set_reduce_smoke(true)
 ck(player.diagnostics().shader_parameter_writes==writes,"repeat option does not upload shader values again")
 player.set_reduce_smoke(false);check_colors(player,false)
 ck(player.snapshot()==original,"turning option off restores exact original snapshot")
 player.set_reduce_smoke(true);player.release(handle);player.set_reduce_smoke(false)
 var pooled_handle:int=player.spawn(TEMPLATE,942,0.0,identity,2.0);player.update_time(0.26);check_colors(player,false)
 player.release(pooled_handle);player.set_reduce_smoke(true);player.spawn(TEMPLATE,942,0.0,identity,2.0);player.update_time(0.26);check_colors(player,true)
 ck(player.diagnostics().nodes_reused>0,"pooled visuals retain current preference without stale alpha")
 player.reset(3);player.spawn(TEMPLATE,942,0.0,identity,2.0);player.update_time(0.26);check_colors(player,true)
 player.set_reduce_smoke(false);check_colors(player,false)
 player.reset(4);player.set_reduce_smoke(true)
 player.spawn("res://data/effects/aru/visual-templates.json#FX_Public_Aru_Hit_Start_1",771,0.0,identity,2.0)
 var flowmap_seen:=false
 for at in [0.05,0.15,0.26,0.4,0.8]:
  player.update_time(at)
  for effect in player._effects:
   for layer in effect.layers:
    for item in layer.particles:
     var descriptor:Dictionary=item.material.get_meta("native_source_descriptor",{})
     if descriptor.get("shader",{}).get("name","")!="DSFX/FX_SHADER_Explosion_Smoke_Flowmap_0":continue
     var raw:Dictionary=Particles.state(layer.params,item.sample,at)
     if not raw.visible:continue
     flowmap_seen=true
     ck(not layer.is_smoke and item.material.get_shader_parameter("particle_color")==raw.color,"Aru Flowmap fire retains original alpha despite smoke-family name")
 ck(flowmap_seen,"real Flowmap fire fixture exercised")
 player.free();finish()
func finish():print("SMOKE VISIBILITY ",checks," checks; ",failures," failures");quit(1 if failures else 0)
