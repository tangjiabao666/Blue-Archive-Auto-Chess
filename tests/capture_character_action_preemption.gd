extends SceneTree
## Paired native actors replay identical real simulator events; only UnitView differs.
const Clock=preload("res://core/character_clock.gd")
const OldView=preload("res://tests/fixtures/unit_view_before_character_polish.gd")
const NewView=preload("res://scripts/unit_view.gd")
const OUT="res://evidence/character-polish/actions/"
var records:Array=[]
func _initialize():call_deferred("run")
func subject(script,actor:Dictionary,profile:Dictionary)->Dictionary:
 var viewport=SubViewport.new();viewport.size=Vector2i(640,640);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 var world=Node3D.new();viewport.add_child(world)
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("e2e8ef");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.8;world.add_child(env)
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);world.add_child(light)
 var view=script.new();world.add_child(view);var shown:Dictionary=actor.duplicate(true);shown.presentation=profile;view.setup(shown,{},1);view._disk.visible=false
 var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.8;world.add_child(camera);camera.current=true
 return {"viewport":viewport,"view":view,"camera":camera}
func run():
 if DisplayServer.get_name()=="headless":printerr("Native renderer required");quit(2);return
 root.title="Blue-A | Character action comparison"
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 for key in ["iori","hina","shiroko"]:
  var clock=Clock.new();clock.generation=1
  var roster:Array=[{"id":0,"team":0,"cell":Vector2(0,0.75),"character_id":key,"star":2 if key=="hina" else 1},{"id":7,"team":1,"cell":Vector2(0,-0.75),"character_id":"aris","star":1}]
  if key=="shiroko":roster.append({"id":8,"team":1,"cell":Vector2(5.5,-6),"character_id":"aris","star":1})
  var err:String=clock.sim.configure(roster,{"random_damage":false,"initial_basic_delay_cap_seconds":5.0})
  if not err.is_empty():printerr(err);quit(1);return
  clock.sim.start()
  for unit in clock.sim.units:
   if unit.id!=0:unit.hp=1 if key=="shiroko" and unit.id==7 else 1000000;unit.max_hp=1000000;unit.busy_until=100000
  var actor:Dictionary=clock.sim.units[0];var old=subject(OldView,actor,profiles[key]);var fixed=subject(NewView,actor,profiles[key])
  # Allow scene/skeleton/renderer registration before a compressed offline replay.
  await process_frame;await RenderingServer.frame_post_draw;await process_frame
  var cast_seen:=false;var trigger:=-1;var captured:=0;var offsets=[1,3,6]
  for frame in range(800):
   var batch:Array=clock.advance(0.05)
   for event in batch:
    old.view.consume(event);fixed.view.consume(event)
    if event.get("actor_id",-1)!=0:continue
    if event.type==("skill" if key=="hina" else "basic"):cast_seen=true
    if trigger<0 and ((key=="shiroko" and event.type=="move") or (key!="shiroko" and cast_seen and event.type=="attack")):trigger=int(event.tick)
   var at:float=clock.sim.tick*0.05
   for item in [old,fixed]:
    item.view.update_time(at,actor);item.camera.position=item.view.position+Vector3(3,1.8,-5);item.camera.look_at(item.view.position+Vector3(0,0.85,0))
   if trigger>=0 and captured<offsets.size() and clock.sim.tick>=trigger+offsets[captured]:
    await process_frame;await RenderingServer.frame_post_draw;await process_frame;await RenderingServer.frame_post_draw
    for mode in ["before","after"]:
     var item:Dictionary=old if mode=="before" else fixed;var file:String=OUT+key+"-"+str(captured)+"-"+mode+".png"
     if item.viewport.get_texture().get_image().save_png(file)!=OK:printerr("capture write failed");quit(1);return
     var bones:Array=[]
     for skeleton in item.view._model.find_children("*","Skeleton3D",true,false):
      for bone in range(skeleton.get_bone_count()):
       var pose:Transform3D=skeleton.get_bone_global_pose(bone)
       if bone<4 or pose.origin.length()>10.0 or pose.basis.get_scale().length()<0.1:bones.append({"name":skeleton.get_bone_name(bone),"origin":str(pose.origin),"scale":str(pose.basis.get_scale()),"det":pose.basis.determinant()})
     records.append({"character":key,"mode":mode,"trigger_tick":trigger,"tick":clock.sim.tick,"file":file,"clip":str(item.view.current_clip),"state":item.view.state,"action_kind":item.view._action_kind,"clip_time":item.view.player.current_animation_position,"position":str(item.view.position),"bones":bones,"model_transform":str(item.view._model.transform),"model_visible":item.view._model.visible})
    captured+=1
   if captured==offsets.size():break
  if captured!=3:printerr("missing captures ",key);quit(1);return
  old.viewport.queue_free();fixed.viewport.queue_free();await process_frame
 var f=FileAccess.open(OUT+"receipt.json",FileAccess.WRITE);f.store_string(JSON.stringify({"scope":"Paired native animation only; shared current materials and identical core events","records":records},"  "));f.close()
 print("CHARACTER_ACTION_CAPTURES frames=",records.size());quit()
