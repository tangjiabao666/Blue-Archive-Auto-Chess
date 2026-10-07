extends SceneTree
const Glue=preload("res://scripts/native_combat_vfx.gd")
const Source=preload("res://vfx/native_source.gd")
var failures:=0
var checks:=0
class AssetView extends Node3D:
 var _model:Node3D
 func muzzle_transform()->Transform3D:return _model.global_transform
 func hit_position()->Vector3:return global_position+Vector3.UP*0.7
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var profiles:Dictionary=Source.read_json("res://data/character-presentations.json")
 var compact:Dictionary=Source.read_json("res://data/effects/battle-events-compact.json")
 var views:Dictionary={};var units:Array=[];var ids:Dictionary={};var idx:=1
 for character in compact.activeRoster:
  var view:=AssetView.new();root.add_child(view)
  view._model=load(profiles[character].model_path).instantiate();view.add_child(view._model)
  view._model.scale*=float(profiles[character].model_scale);view._model.rotation.y=float(profiles[character].model_yaw)
  views[idx]=view;ids[character]=idx;units.append({"id":idx,"character_id":character});idx+=1
 var glue:=Glue.new();root.add_child(glue);glue.configure(profiles);glue.begin_roster(views,units,44)
 for character in compact.activeRoster:
  var paths:Dictionary={}
  for timeline in compact.characters[character].timelines:
   if timeline.kind not in ["ex","basic"]:continue
   for event in timeline.events:
    if event.kind!="effect":continue
    for binding in event.bindings:
     if str(binding.get("hierarchy","")).is_empty():continue
     paths[binding.hierarchy]=true
  for path in paths:
   ck(glue.resolve_live_anchor(ids[character],path)!=null,"real GLB anchor "+path)
  print("ASSET_ANCHORS ",character," checked=",paths.size())
 var yuuka=views[ids.yuuka]
 var animations:Array=yuuka._model.find_children("*","AnimationPlayer",true,false)
 ck(not animations.is_empty(),"Yuuka native AnimationPlayer")
 if not animations.is_empty():
  var player:AnimationPlayer=animations[0];player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
  player.play(StringName(profiles.yuuka.clips.ex));player.advance(0.0)
  var initial=glue.resolve_live_anchor(ids.yuuka,"Yuuka_Original/bone_Calculator")
  player.advance(1.0)
  var later=glue.resolve_live_anchor(ids.yuuka,"Yuuka_Original/bone_Calculator")
  ck(initial!=null and later!=null and not (initial as Transform3D).is_equal_approx(later),"calculator follows live animated bone rather than static rest offset")
 ck(glue.resolve_live_anchor(ids.shiroko,"FX_Shiroko_Original_Drone_Mesh/bone_dron_com")==null,"foreign nested drone source root is not matched on actor")
 glue.update_time(0)
 for character in compact.activeRoster:glue.consume({"type":"skill","ability":"ex","actor_id":ids[character],"tick":0,"generation":44,"event_id":"ex-"+character},units)
 glue.update_time(0.5)
 ck(glue.diagnostics().timelines_spawned==units.size(),"one native EX timeline handle per requested roster actor")
 ck(glue.diagnostics().native.visible_particles>0,"real roster source layers visible")
 for issue in glue.diagnostics().issues:print("ASSET_GLUE_DIAGNOSTIC ",issue.code," ",issue.context)
 glue.reset(45);glue.free()
 for view in views.values():view.free()
 print("COMBAT_VFX_ASSETS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
