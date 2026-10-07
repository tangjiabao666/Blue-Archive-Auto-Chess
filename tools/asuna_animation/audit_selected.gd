extends SceneTree
var BASE:String
func vec(v):
 if v is Vector3:return [v.x,v.y,v.z]
 if v is Quaternion:return [v.x,v.y,v.z,v.w]
 assert(false,"Unexpected property type")
 return []
func transform_data(t:Transform3D):
 return {"translation":vec(t.origin),"rotation":vec(t.basis.get_rotation_quaternion()),"scale":vec(t.basis.get_scale()),"basis":[vec(t.basis.x),vec(t.basis.y),vec(t.basis.z)]}
func _initialize():call_deferred("run")
func run():
 var args=OS.get_cmdline_user_args()
 if args.size()!=1:printerr("Expected audit output directory with probes.json");quit(2);return
 BASE=String(args[0]).trim_suffix("/")+"/"
 var request=JSON.parse_string(FileAccess.get_file_as_string(BASE+"probes.json"))
 var scene=load("res://assets/characters/asuna/asuna.glb").instantiate();root.add_child(scene)
 var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json")).asuna
 var view=load("res://scripts/unit_view.gd").new();root.add_child(view)
 view.setup({"id":91,"character_id":"asuna","team":0,"cell":Vector2.ZERO,"range":3.0,"attack_ticks":60,"presentation":profile},{},7)
 var player:AnimationPlayer=view.player
 if player==null or not view.diagnostics().warnings.is_empty():printerr("UnitView selection failed: ",view.diagnostics());quit(1);return
 var selected:AnimationLibrary=player.get_animation_library("")
 assert(selected.get_meta("source_glb_sha256","")==profile.source_glb_sha256,"Selected library provenance mismatch")
 var report={"version":Engine.get_version_info(),"clips":{},"nodes":[],"bones":[],"consumer":"UnitView","selected_library_sha256":profile.animation_library_sha256,"declared_source_glb_sha256":selected.get_meta("source_glb_sha256"),"metadata_rest_source":"Separate initial imported model instance, before UnitView starts its idle animation"}
 for node in scene.find_children("*","Node3D",true,false):
  report.nodes.append({"name":str(node.name),"path":str(scene.get_path_to(node)),"transform":transform_data(node.transform)})
  if node is Skeleton3D:
   for i in node.get_bone_count():
    report.bones.append({"name":node.get_bone_name(i),"parent":node.get_bone_parent(i),"rest":transform_data(node.get_bone_rest(i)),"pose":transform_data(node.get_bone_pose(i))})
 var binary=FileAccess.open(BASE+"samples.bin",FileAccess.WRITE)
 var sample_count=0
 for name in request:
  var animation:Animation=player.get_animation(name)
  assert(animation!=null,"Missing clip "+name)
  var tracks=[]
  for req in request[name]:
   var i=int(req.track)
   assert(animation.track_get_type(i)==int(req.type),"Track type mismatch")
   var keys=[]
   for k in animation.track_get_key_count(i):keys.append([animation.track_get_key_time(i,k),vec(animation.track_get_key_value(i,k))])
   tracks.append({"index":i,"path":str(animation.track_get_path(i)),"type":animation.track_get_type(i),"interpolation":animation.track_get_interpolation_type(i),"enabled":animation.track_is_enabled(i),"loop_wrap":animation.track_get_interpolation_loop_wrap(i),"keys":keys})
   for time in req.times:
    var value
    match int(req.type):
     Animation.TYPE_POSITION_3D:value=animation.position_track_interpolate(i,time)
     Animation.TYPE_ROTATION_3D:value=animation.rotation_track_interpolate(i,time)
     Animation.TYPE_SCALE_3D:value=animation.scale_track_interpolate(i,time)
     _:assert(false,"Unsupported track type")
    for x in vec(value):
     assert(is_finite(x),"Nonfinite result")
     binary.store_double(x)
    sample_count+=1
  report.clips[name]={"length":animation.length,"loop_mode":animation.loop_mode,"tracks":tracks}
  print("SAMPLED ",name," total calls=",sample_count)
 binary.close()
 report.sample_count=sample_count
 FileAccess.open(BASE+"runtime.json",FileAccess.WRITE).store_string(JSON.stringify(report))
 view.free();scene.free();print("AUDIT_SAMPLING_COMPLETE ",sample_count);quit()
