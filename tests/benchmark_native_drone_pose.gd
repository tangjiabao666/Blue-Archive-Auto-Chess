extends SceneTree
## Warmed component evaluation only, excluding particles/pose export/rendering.
## The native reference intentionally emits its two known first-seek errors.
const Props=preload("res://scripts/native_skill_props.gd")
const ITERATIONS=10000
func _initialize()->void:call_deferred("run")
func run()->void:
 var props:=Props.new();root.add_child(props)
 var container:Node3D=load(Props.MODEL).instantiate();root.add_child(container)
 var player:AnimationPlayer=container.find_children("*","AnimationPlayer",true,false)[0]
 var skeleton:Skeleton3D=container.find_children("*","Skeleton3D",true,false)[0]
 var prop_root:Node3D=container.find_child("FX_Shiroko_Original_Drone_Mesh",true,false)
 var animation:Animation=player.get_animation("Recorded")
 var instance:Dictionary={"animation":animation,"skeleton":skeleton,"root":prop_root,"pose_tracks":props._bind_pose_tracks(animation,player,skeleton,prop_root)}
 player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 player.play("Recorded");player.seek(0.0,true)
 var native:Array=[];var adapter:Array=[]
 for batch in 7:
  var started:int=Time.get_ticks_usec()
  for i in ITERATIONS:player.seek(float(i%5760)/960.0,true)
  native.append(float(Time.get_ticks_usec()-started)/ITERATIONS)
  started=Time.get_ticks_usec()
  for i in ITERATIONS:props._seek_pose(instance,float(i%5760)/960.0)
  adapter.append(float(Time.get_ticks_usec()-started)/ITERATIONS)
 native.sort();adapter.sort()
 print("DRONE_POSE_BENCHMARK native_median_us=",native[3]," adapter_median_us=",adapter[3]," native_batches=",native," adapter_batches=",adapter)
 container.free();props.free();quit()
