extends SceneTree
## CPU-only paired benchmark. Optional: -- --baseline /absolute/path/to/unit_view.gd
## Does not represent GPU/frame throughput or a 60 FPS acceptance test.
func _initialize():call_deferred("run")
func fixture(script:GDScript)->Dictionary:
 var profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 var names=["shiroko","hoshino","hina","aru","yuuka","aris","serika","yuuka"]
 var views:Array=[];var units:Array=[]
 for i in range(8):
  var unit={"id":i,"team":i/4,"cell":Vector2(i%4,3 if i<4 else -3),"range":3.0,"presentation":profiles[names[i]]}
  var view=script.new();root.add_child(view);view.setup(unit,{},1);views.append(view);units.append(unit)
 return {"views":views,"units":units,"update_us":0,"anchors_us":0,"frames":0}
func sample(group:Dictionary,at:float)->void:
 var before:=Time.get_ticks_usec()
 for i in range(8):group.views[i].update_time(at,group.units[i]);group.views[i].set_selected(false)
 group.update_us+=Time.get_ticks_usec()-before
 before=Time.get_ticks_usec()
 for view in group.views:view.hit_position();view.muzzle_transform()
 group.anchors_us+=Time.get_ticks_usec()-before;group.frames+=1
func run():
 var candidates:Dictionary={"current":fixture(load("res://scripts/unit_view.gd"))}
 var args=OS.get_cmdline_user_args()
 for i in range(args.size()-1):
  if args[i]=="--baseline":candidates["baseline"]=fixture(load(args[i+1]))
 var order:Array=candidates.keys()
 for frame in range(1800):
  if frame%120==0:order.reverse()
  for key in order:sample(candidates[key],float(frame)/60.0)
 for key in candidates:
  var group:Dictionary=candidates[key]
  print("UNIT_VIEW_CPU ",JSON.stringify({"variant":key,"actors":8,"frames":group.frames,"update_mean_ms":float(group.update_us)/group.frames/1000.0,"anchors_mean_ms":float(group.anchors_us)/group.frames/1000.0}))
  for view in group.views:view.queue_free()
 await process_frame;quit()
