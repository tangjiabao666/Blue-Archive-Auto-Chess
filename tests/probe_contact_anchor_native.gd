extends SceneTree
## Run separately with -- --ticked or -- --batched; use --out=/absolute/path/stem.
## Native actors, full particle renderer, and the audited real-Core SG retarget.
const Clock=preload("res://core/character_clock.gd")
class CaptureStage extends "res://scripts/battle_stage.gd":
 func _update_camera(_at:float)->void:pass
func _initialize():call_deferred("run")
func run():
 var batched:bool=OS.get_cmdline_user_args().has("--batched")
 var out:String="/tmp/contact-anchor-"+("batched" if batched else "ticked")
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
 var clock=Clock.new();clock.generation=1
 var roster=[{"id":1,"team":0,"cell":Vector2(0,.75),"character_id":"hoshino","star":1},{"id":2,"team":1,"cell":Vector2(0,-.75),"character_id":"aris","star":1},{"id":3,"team":1,"cell":Vector2(2,-.75),"character_id":"aris","star":1}]
 assert(clock.sim.configure(roster,{"random_damage":false}).is_empty());clock.sim.start()
 clock.sim.units[1].hp=1;clock.sim.units[1].busy_until=100000;clock.sim.units[2].hp=1000000;clock.sim.units[2].max_hp=1000000;clock.sim.units[2].busy_until=100000
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 var stage=CaptureStage.new();root.add_child(stage);stage.configure(profiles,[]);stage.set_roster(clock.sim.units,1,false)
 stage.hud.visible=false
 stage.camera.size=3.5;stage.camera.h_offset=0;stage.camera.v_offset=0
 stage.camera.position=Vector3(-3,2.2,4);stage.camera.look_at(Vector3(0,.8,.7))
 if batched:stage.update_display(clock.sim.units,clock.advance(.03),.03,clock.sim.tick)
 var contact:Dictionary={}
 while contact.is_empty():
  var events:Array=clock.advance(.08 if batched else .05)
  for event in events:
   if event.type=="damage" and event.actor_id==1 and event.target_id==3 and event.ability=="normal":contact=event
  stage.update_display(clock.sim.units,events,clock.sim.tick*.05+clock.accumulator,clock.sim.tick)
 # Match the same visible particle age, while preserving each historical sampling route.
 stage.update_display(clock.sim.units,[],3.31,clock.sim.tick)
 var glue=stage.native_vfx
 var particles:Array=[]
 var anchor:Variant=null
 for effect in glue._player._effects:
  if not is_equal_approx(float(effect.start),3.30) or not str(effect.prefab).contains("Muzzle_SG"):continue
  anchor=effect.resolver.call({"_native_anchor_query":"birth"}, {},3.30)
  for layer in effect.layers:
   for particle in layer.particles:
    if effect.node.visible and particle.node.visible:
     particles.append({"layer":layer.path,"world_space":int(layer.params.get("moveWithTransform",0))==1,"birth":particle.birth,"transform":particle.node.global_transform})
 var result={"mode":"batched" if batched else "ticked","contact_tick":contact.tick,"contact_time":float(contact.tick)*.05,"render_time":3.31,"anchor":anchor,"particles":particles,"diagnostics":glue.diagnostics()}
 var file=FileAccess.open(out+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
 if DisplayServer.get_name()!="headless":
  await process_frame;await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(out+".png")
 print("CONTACT_NATIVE_CAPTURE ",out," contact=",contact.tick," particles=",particles.size()," anchor=",anchor)
 stage.free();quit()
