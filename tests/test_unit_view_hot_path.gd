extends SceneTree
## Rendering caches must not change live anchors, public diagnostics or selection.
var failures:=0
var checks:=0
class ObservedView extends "res://scripts/unit_view.gd":
 var diagnostic_builds:=0
 func _refresh_diagnostics()->void:
  diagnostic_builds+=1
  super._refresh_diagnostics()
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize():call_deferred("run")
func reference_hit(view:Node3D)->Vector3:
 var skeletons=view._model.find_children("*","Skeleton3D",true,false)
 if skeletons.is_empty():return view.global_position+Vector3.UP*0.7
 var skeleton:Skeleton3D=skeletons[0]
 var bone:=skeleton.find_bone("Bip001 Spine1")
 return skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin if bone>=0 else view.global_position+Vector3.UP*0.7
func reference_muzzle(view:Node3D) -> Transform3D:
 # Original CH0331/Bip001_Weapon/fire_01 socket, Unity -> FBX X reflection,
 # centimeter import scale. Read the live bone pose, never move authored bones.
 var skeletons = view._model.find_children("*","Skeleton3D",true,false)
 if skeletons.is_empty():return view.global_transform
 var skeleton: Skeleton3D = skeletons[0]
 var anchor_name:String=view._presentation.get("muzzle_anchor","")
 if not anchor_name.is_empty():
  for source_anchor in view._presentation.get("anchors",[]):
   if source_anchor.name!=anchor_name:continue
   var parts:PackedStringArray=String(source_anchor.path).split("/")
   var parent_index:=skeleton.find_bone(parts[parts.size()-2])
   if parent_index>=0:
    var p:Array=source_anchor.local_translation;var q:Array=source_anchor.local_rotation
    var socket_native:=Transform3D(Basis(Quaternion(q[0],q[1],q[2],q[3])),Vector3(p[0],p[1],p[2]))
    return skeleton.global_transform*skeleton.get_bone_global_pose(parent_index)*socket_native
  for node in view._model.find_children(anchor_name,"Node3D",true,false):return node.global_transform
 var weapon := skeleton.find_bone("Bip001_Weapon")
 if weapon < 0:return view.global_transform
 var socket := Transform3D(Basis(Quaternion(0.0000001686,0.0000001686,0.707106352,0.707107246)),Vector3(-0.0000000001278722,-0.000137883760,0.001284404695))
 return skeleton.global_transform * skeleton.get_bone_global_pose(weapon) * socket


func run():
 var profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 var view:=ObservedView.new();root.add_child(view)
 var generation:=0
 for key in ["shiroko","yuuka","hoshino","hina","aru","aris","serika"]:
  generation+=1
  var unit={"id":4,"team":0,"cell":Vector2(1,2),"range":3.0,"presentation":profiles[key],"shield":23,"shield_until":90}
  view.setup(unit,{},generation)
  ck(view._disk_material.albedo_color.is_equal_approx(Color("4b9ade",0.38)),"new model receives unselected team color")
  view.diagnostic_builds=0
  for i in range(60):
   view.update_time(float(i)/60.0,unit);view.set_selected(false)
  ck(view.diagnostic_builds==0,"unobserved animation frames do not rebuild diagnostics")
  var info:Dictionary=view.diagnostic_info
  ck(info.actor_id==4 and is_equal_approx(info.clock,59.0/60.0) and info.shield==23,"public diagnostic_info remains current")
  ck(info.native_animation_count==view.player.get_animation_list().size(),"cached animation count matches loaded library")
  ck(view.diagnostic_builds==1,"direct diagnostic property builds only when observed")
  var copy:Dictionary=view.diagnostics();copy.warnings.append("caller-only")
  ck(not view.diagnostics().warnings.has("caller-only"),"diagnostics keeps defensive copy semantics")
  view.set_selected(true)
  ck(view._range_indicator.visible and view._disk_material.albedo_color.is_equal_approx(Color("f3d98b",0.92)),"changed selection updates range and material")
  var before:int=view.diagnostic_builds
  for i in range(60):view.set_selected(true)
  ck(view.diagnostic_builds==before,"unchanged selection performs no diagnostics work")
  for at in [0.0,0.33,0.7,1.5]:
   view.player.play(view.ATTACK_FIRE);view.player.seek(at,true)
   ck(view.hit_position().is_equal_approx(reference_hit(view)),"cached hit bone follows live animation for "+key)
   var p:Transform3D=view.muzzle_transform()
   ck(p.is_equal_approx(reference_muzzle(view)),"cached muzzle preserves original socket formula for "+key)
   view.position.x+=1.0
   var q:Transform3D=view.muzzle_transform()
   ck((q.origin-p.origin).is_equal_approx(Vector3.RIGHT),"cached muzzle follows moving actor for "+key)
 view.queue_free();await process_frame
 print("UNIT_VIEW_HOT_PATH ",checks," checks; ",failures," failures");quit(1 if failures else 0)
