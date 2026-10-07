extends SceneTree
## Source firing channels must finish their transition by authoritative contact.
const Clock=preload("res://core/character_clock.gd")
const View=preload("res://scripts/unit_view.gd")
var checks:=0
var failures:=0
var profiles:Dictionary
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize():call_deferred("run")
func tracked_mismatches(actual,reference)->Dictionary:
 var clip:Animation=actual.player.get_animation(actual.ATTACK_FIRE)
 var aroot:Node=actual.player.get_node(actual.player.root_node);var broot:Node=reference.player.get_node(reference.player.root_node)
 var compared:=0;var differences:Array=[]
 for i in clip.get_track_count():
  var kind:int=clip.track_get_type(i)
  if kind not in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:continue
  var path:NodePath=clip.track_get_path(i);var names:NodePath=NodePath(path.get_concatenated_names())
  var a=aroot.get_node_or_null(names);var b=broot.get_node_or_null(names)
  if a==null or b==null:continue
  var av;var bv
  if a is Skeleton3D and path.get_subname_count()>0:
   var bone:int=a.find_bone(path.get_subname(0));var other:int=b.find_bone(path.get_subname(0))
   if bone<0 or other<0:continue
   av=a.get_bone_pose_position(bone) if kind==Animation.TYPE_POSITION_3D else a.get_bone_pose_rotation(bone) if kind==Animation.TYPE_ROTATION_3D else a.get_bone_pose_scale(bone)
   bv=b.get_bone_pose_position(other) if kind==Animation.TYPE_POSITION_3D else b.get_bone_pose_rotation(other) if kind==Animation.TYPE_ROTATION_3D else b.get_bone_pose_scale(other)
  elif a is Node3D:
   av=a.position if kind==Animation.TYPE_POSITION_3D else a.quaternion if kind==Animation.TYPE_ROTATION_3D else a.scale
   bv=b.position if kind==Animation.TYPE_POSITION_3D else b.quaternion if kind==Animation.TYPE_ROTATION_3D else b.scale
  else:continue
  compared+=1
  var same:bool=absf(av.dot(bv))>0.999999 if kind==Animation.TYPE_ROTATION_3D else av.is_equal_approx(bv)
  if not same:differences.append(str(path))
 return {"compared":compared,"differences":differences}
func exercise(key:String,delta:float,after_ability:bool=true,desired_shot:int=1):
 var clock=Clock.new();clock.generation=1
 ck(clock.sim.configure([{"id":0,"team":0,"cell":Vector2(0,.75),"character_id":key,"star":2 if key=="hina" else 1},{"id":7,"team":1,"cell":Vector2(0,-.75),"character_id":"aris","star":1}],{"random_damage":false,"initial_basic_delay_cap_seconds":5.0}).is_empty(),"pose fixture configures")
 clock.sim.start();clock.sim.units[1].hp=1000000;clock.sim.units[1].max_hp=1000000;clock.sim.units[1].busy_until=100000
 var actor:Dictionary=clock.sim.units[0];var shown:Dictionary=actor.duplicate(true);shown.presentation=profiles[key]
 var view=View.new();root.add_child(view);view.setup(shown,{},1)
 var reference=View.new();root.add_child(reference);reference.setup(shown,{},1)
 var cast_seen:bool=not after_ability;var shot:Dictionary={};var found:=false;var shot_count:=0
 for frame in range(2000):
  var contact:=false
  for event in clock.advance(delta):
   view.consume(event)
   if event.get("actor_id",-1)!=0:continue
   if event.type==("skill" if key=="hina" else "basic"):cast_seen=true
   if cast_seen and event.type=="attack":
    shot_count+=1
    if shot_count==desired_shot:shot=event.duplicate(true)
   if not shot.is_empty() and event.type in ["damage","miss"] and event.get("ability","")=="normal":contact=true
  view.update_time(clock.sim.tick*.05+clock.accumulator,actor)
  if contact:
   found=true;reference._face_point(View.cell_position(shot.target_cell))
   reference.player.play(view.ATTACK_FIRE,0.0,1.0);reference.player.seek(view.player.current_animation_position,true);reference.player.advance(0.0)
   var result:Dictionary=tracked_mismatches(view,reference)
   ck(result.compared>20,"source comparison covers actual native firing tracks")
   ck(result.differences.is_empty(),"%s %.2fFPS shot%d ability=%s contact has source firing pose; mismatched=%d first=%s"%[key,1.0/delta,desired_shot,str(after_ability),result.differences.size(),str(result.differences.slice(0,3))])
   break
 ck(found,"real core reaches post-ability first contact")
 view.free();reference.free()
func run():
 profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 for delta in [1.0/60.0,.05,.08]:
  for key in ["iori","hina"]:exercise(key,delta)
 # This gate drives real combat. Presentation-only staging profiles have no
 # combat definition yet; their source clips are verified in separate gates.
 var active:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/character_skills.json")).active_roster
 for key in active:
  ck(profiles.has(key),"every active combat character has a native profile")
  exercise(key,.05,false,1);exercise(key,.05,false,2)
 await process_frame;print("NATIVE FIRST SHOT POSE ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
