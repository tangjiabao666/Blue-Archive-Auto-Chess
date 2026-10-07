extends SceneTree
const Stage=preload("res://scripts/battle_stage.gd")
const Player=preload("res://vfx/native_effect_player.gd")
const Stretch=preload("res://vfx/native_stretch_orientation.gd")
class FrameConsumer extends Node3D:
 var _player:Node3D
 var snapshots:Array=[]
 func _init():_player=Player.new();add_child(_player)
 func reset(generation:int)->void:_player.reset(generation)
 func update_time(at:float)->void:
  snapshots.append(_player.stretch_camera_at.call(at) if _player.stretch_camera_at.is_valid() else {})
class IdleConsumer extends Node3D:
 func reset(_generation:int)->void:pass
 func update_time(_at:float)->void:pass
class IsolatedStage extends Stage:
 func _ready()->void:
  camera=Camera3D.new();add_child(camera)
  camera.projection=Camera3D.PROJECTION_ORTHOGONAL
  camera.position=Vector3(-11,8,14);camera.look_at(Vector3(0,0.2,0))
  native_vfx=FrameConsumer.new();add_child(native_vfx)
  native_props=IdleConsumer.new();add_child(native_props)
  native_mines=IdleConsumer.new();add_child(native_mines)
  preparation=false
 func _update_actors(_at:float,_tick:int=-1)->void:pass
var checks:=0
var failed:=0
func ck(v:bool,label:String):
 checks+=1
 if not v:failed+=1;printerr("FAIL: "+label)
func _initialize():call_deferred("run")
func run():
 var stage=IsolatedStage.new();root.add_child(stage)
 var units:Array=[{"hp":100,"cell":Vector2(-2,-1)},{"hp":100,"cell":Vector2(3,2)}]
 stage.update_display(units,[],0.5,10)
 var first:Dictionary=stage.native_vfx.snapshots[-1]
 ck(not first.is_empty(),"BattleStage provides camera snapshot before VFX update")
 if first.is_empty():stage.free();finish();return
 ck(first.time==0.5,"snapshot uses absolute battle time")
 ck(first.transform==stage.camera.get_camera_transform(),"snapshot observes post-update actual camera including offsets")
 ck(first.transform!=stage.camera.global_transform,"nonzero camera offsets are included")
 ck(first.projection=="orthographic","orthographic projection supplied")
 var before:Transform3D=stage.camera.global_transform
 var frozen:Transform3D=first.transform
 stage.camera.position+=Vector3(7,2,1)
 var same_frame:Dictionary=stage.native_vfx._player.stretch_camera_at.call(0.5)
 ck(same_frame.transform==frozen,"snapshot frozen against later camera mutation")
 ck(stage.native_vfx._player.stretch_camera_at.call(0.4).is_empty(),"stale absolute time rejected")
 first.transform=Transform3D.IDENTITY
 ck(stage.native_vfx._player.stretch_camera_at.call(0.5).transform==frozen,"consumer cannot mutate stored snapshot")
 stage.camera.transform=before
 stage.camera.projection=Camera3D.PROJECTION_PERSPECTIVE
 stage.update_display(units,[],0.6,12)
 var perspective:Dictionary=stage.native_vfx.snapshots[-1]
 ck(perspective.projection=="perspective","perspective mode reported")
 var legacy:=Transform3D(Basis.IDENTITY.scaled(Vector3(0.1,2,0.1)),Vector3.ZERO)
 var oriented:Dictionary=Stretch.orient(legacy,Vector3.RIGHT,perspective,0.6)
 ck(oriented.applied,"snapshot accepted by actual orientation helper")
 stage.camera.projection=Camera3D.PROJECTION_FRUSTUM
 stage.update_display(units,[],0.7,14)
 var unsupported:Dictionary=stage.native_vfx.snapshots[-1]
 ck(unsupported.is_empty(),"unsupported frustum projection yields empty snapshot")
 ck(not Stretch.orient(legacy,Vector3.RIGHT,unsupported,0.7).applied,"unsupported camera preserves helper fallback")
 var actual_camera:Camera3D=stage.camera
 stage.camera=null
 stage._stretch_camera_frame=stage._capture_stretch_camera(0.8)
 ck(stage._stretch_camera_frame.is_empty(),"missing camera returns empty snapshot")
 ck(stage.native_vfx._player.stretch_camera_at.call(0.8).is_empty(),"missing camera cannot reuse prior frame")
 ck(not Stretch.orient(legacy,Vector3.RIGHT,stage._stretch_camera_frame,0.8).applied,"missing camera retains legacy fallback")
 stage.camera=actual_camera
 ck(stage._capture_stretch_camera(NAN).is_empty(),"nonfinite absolute time rejected")
 ck(stage._resolve_stretch_camera(NAN).is_empty(),"nonfinite callback query rejected")
 stage.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 stage.update_display(units,[],0.5,10)
 ck(stage.native_vfx.snapshots[-1].time==0.5,"rewound frame gets its current explicit timestamp")
 ck(stage.native_vfx.snapshots[-1].transform==stage.camera.get_camera_transform(),"rewound frame captures actual current camera")
 stage.set_roster([],7,true)
 ck(stage.native_vfx._player.stretch_camera_at.call(0.5).is_empty(),"roster reset clears prior-frame camera snapshot")
 stage.free();finish()
func finish():
 print("STAGE_CAMERA checks=",checks," failures=",failed);quit(1 if failed else 0)
