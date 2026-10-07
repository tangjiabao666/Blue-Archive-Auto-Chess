extends SceneTree
const Props=preload("res://scripts/native_skill_props.gd")
const Source=preload("res://vfx/native_source.gd")
var checks:=0
var failures:=0
class AssetView extends Node3D:
 var _model:Node3D
 var is_dead:=false
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var profiles:Dictionary=Source.read_json("res://data/character-presentations.json")
 var view:=AssetView.new();root.add_child(view)
 view._model=load(profiles.shiroko.model_path).instantiate();view.add_child(view._model)
 view._model.scale*=float(profiles.shiroko.model_scale);view._model.rotation.y=float(profiles.shiroko.model_yaw)
 view.position=Vector3(4,0,2);view.rotation.y=0.7
 var props:=Props.new();root.add_child(props);props.configure(profiles)
 var units=[{"id":9,"character_id":"shiroko"}];props.begin_roster({9:view},units,19)
 props.consume({"type":"skill","ability":"ex","actor_id":9,"tick":0,"generation":19,"event_id":"asset-ex"},units)
 props.update_time(3.0)
 ck(props.diagnostics().active_props==1,"actual imported character accepts source-bound drone")
 if props._active.has(9):
  var item:Dictionary=props._active[9]
  ck(item.container.global_transform.is_equal_approx(view._model.global_transform),"pruned source identity Ex_Root inherits actual model transform once")
  ck(item.animation.get_track_count()==10,"all source animated prop bindings imported")
  ck(is_equal_approx(item.animation.length,6.0),"native prop duration exact")
  for i in item.animation.get_track_count():ck(item.animation.track_get_key_count(i)==5761,"960 Hz runtime track "+str(i))
  ck(item.player.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,"wall-clock animation disabled")
  var before:Dictionary=props._particles.snapshot()
  props.update_time(3.0);ck(before==props._particles.snapshot(),"pause preserves source particle snapshot")
  var bone:Transform3D=item.skeleton.global_transform*item.skeleton.get_bone_global_pose(item.bone)
  var got:Transform3D=props._resolve_muzzle({}, {}, 3.0,9)
  ck(got.is_equal_approx(bone*Transform3D(Props.PARTICLE_BRIDGE,Vector3.ZERO)),"actual imported muzzle bone includes arbitrary actor rotation")
  var body=item.container.find_child("Siroko_Dron",true,false)
  var material:ShaderMaterial=body.get_active_material(0)
  ck(material.get_shader_parameter("source_texture")!=null,"original weapon mask is available")
  ck(is_equal_approx(float(material.get_shader_parameter("light_value")),0.3499999940395355),"native drone material property retained")
  view.position.x=6.0;props.update_time(4.0)
  var historical:Transform3D=props._sample_anchor(9,3.5)
  ck(is_equal_approx(historical.origin.x,5.0),"moving actor historical root interpolates for particle births")
 var packed:PackedScene=load(Props.MODEL)
 ck(packed!=null,"new GLB is a loadable exported scene resource")
 for name in ["runtime-metadata.json","material-bindings.json","manifest.json","Shiroko_Dron_3433468466433650992.png","Shiroko_Dron_Mask_3186761713445147604.png","shiroko_Dron_Wing_6261044633261688795.png"]:
  ck(FileAccess.file_exists(Props.ASSET_DIR+name) or ResourceLoader.exists(Props.ASSET_DIR+name),"export dependency "+name)
 props.update_time(6.0);ck(props.diagnostics().active_props==0 and props._particles.get("_effects").is_empty(),"exact source end frees mesh and nested effect")
 props.reset(20);props.free();view.free()
 print("SKILL_PROP_ASSETS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
