extends SceneTree
const Props=preload("res://scripts/native_skill_props.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var props:=Props.new();root.add_child(props)
 var container:Node3D=load(Props.MODEL).instantiate();root.add_child(container)
 var player:AnimationPlayer=container.find_children("*","AnimationPlayer",true,false)[0]
 player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 player.active=false
 var skeleton:Skeleton3D=container.find_children("*","Skeleton3D",true,false)[0]
 var prop_root:Node3D=container.find_child("FX_Shiroko_Original_Drone_Mesh",true,false)
 var source:Animation=player.get_animation("Recorded")
 ck(props._bind_pose_tracks(source,player,skeleton,prop_root).size()==10,"all ten original tracks supported")
 for mutation in ["type","missing","disabled","empty","bone","duplicate","target"]:
  var altered:Animation=source.duplicate()
  match mutation:
   "type":
    var track:int=altered.add_track(Animation.TYPE_VALUE)
    altered.track_set_path(track,NodePath("FX_Shiroko_Original_Drone_Mesh:visible"))
    altered.track_insert_key(track,0.0,true)
   "missing":altered.remove_track(0)
   "disabled":altered.track_set_enabled(0,false)
   "empty":
    var path:NodePath=altered.track_get_path(0)
    altered.remove_track(0)
    altered.track_set_path(altered.add_track(Animation.TYPE_POSITION_3D),path)
   "bone":
    var path:NodePath=altered.track_get_path(2)
    altered.track_set_path(2,NodePath(str(path).get_slice(":",0)+":bone_dron_com"))
   "duplicate":
    var track:int=altered.add_track(Animation.TYPE_POSITION_3D)
    altered.track_set_path(track,altered.track_get_path(0))
    altered.position_track_insert_key(track,0.0,Vector3.ZERO)
   "target":altered.track_set_path(0,NodePath("MissingNode"))
  props._issues.clear();props._issue_keys.clear()
  for attempt in 3:ck(props._bind_pose_tracks(altered,player,skeleton,prop_root).is_empty(),mutation+" fails closed")
  ck(props._issues.size()==1,mutation+" reports one deduplicated issue")
 ck(source.get_track_count()==10 and source.track_is_enabled(0),"shared source animation remains untouched")
 ck(player.get_animation("Recorded")==source,"original animation resource remains installed")
 container.free();props.free()
 print("DRONE_LAYOUT_TESTS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
