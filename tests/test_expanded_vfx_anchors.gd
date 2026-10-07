extends SceneTree
const Glue=preload("res://scripts/native_combat_vfx.gd")
const Source=preload("res://vfx/native_source.gd")
const CHARACTERS=["iori","tsubaki","nonomi","mutsuki","haruna","koharu"]
var checks:=0
var failures:=0
class View extends Node3D:
 var _model:Node3D
 func hit_position()->Vector3:return global_position+Vector3.UP*0.7
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var profiles:Dictionary=Source.read_json("res://data/character-presentations.json")
 var compact:Dictionary=Source.read_json("res://data/effects/battle-events-compact.json")
 var views:Dictionary={};var ids:Dictionary={};var units:Array=[]
 for char in CHARACTERS:
  if not profiles.has(char) or not compact.characters.has(char):continue # Report unavailable roster members below rather than failing to parse a model.
  var view:=View.new();root.add_child(view)
  view._model=load(profiles[char].model_path).instantiate();view.add_child(view._model)
  view._model.scale*=float(profiles[char].model_scale);view._model.rotation.y=float(profiles[char].model_yaw)
  var id:int=views.size()+1;views[id]=view;ids[char]=id;units.append({"id":id,"character_id":char})
 ck(views.size()==CHARACTERS.size(),"all six expanded source GLBs and timelines are available")
 var glue:=Glue.new();root.add_child(glue);glue.configure(profiles);glue.begin_roster(views,units,31)
 var bound_paths:=0
 for char in ids:
  var paths:Dictionary={}
  for timeline in compact.characters[char].timelines:
   if timeline.kind not in ["ex","basic"]:continue
   for event in timeline.events:
    if event.kind!="effect":continue
    for binding in event.bindings:
     if not str(binding.get("hierarchy","")).is_empty():paths[binding.hierarchy]=true
  for path in paths:
   ck(glue.resolve_live_anchor(ids[char],path)!=null,"real expanded source binding "+path);bound_paths+=1
  ck(glue._sample_anchor(ids[char],"@muzzle",0.0)!=null,"real expanded ordinary source muzzle "+char)
  ck(glue.resolve_live_anchor(ids[char],"Foreign_Original/Ex_Root")==null,"foreign roots remain forbidden "+char)
 # Force the importer-pruning case after checking every real source binding.
 for char in ids:
  for node in glue._indices[ids[char]].names.get("Ex_Root",[]):
   if is_instance_valid(node):node.free()
  ck(glue.resolve_live_anchor(ids[char],str(glue._source_roots[char])+"/Ex_Root")!=null,"source-proven pruned Ex_Root "+char)
  if char in ["iori","koharu"]:ck(glue.resolve_live_anchor(ids[char],str(glue._source_roots[char])+"/Ex_Root/FX_Local_DM")!=null,"source-proven pruned FX_Local_DM "+char)
 # Iori's static FX_Rotate local TRS must inherit the animated bone_root, never actor root.
 var iori_id:int=ids.iori
 var parent_matches:Array=glue._indices[iori_id].names.get("bone_root",[])
 ck(parent_matches.size()==1,"Iori retains exact source parent bone_root")
 if parent_matches.size()==1:
  var parent:Node3D=parent_matches[0]
  for node in glue._indices[iori_id].names.get("FX_Rotate",[]):
   if is_instance_valid(node):node.free()
  var before=glue.resolve_live_anchor(iori_id,"Iori_Original/bone_root/FX_Rotate")
  parent.position+=Vector3(0.45,0.2,-0.3)
  var after=glue.resolve_live_anchor(iori_id,"Iori_Original/bone_root/FX_Rotate")
  var expected:Transform3D=parent.global_transform*Transform3D(Glue.REFLECTION_BRIDGE,Vector3.ZERO)
  ck(after!=null and (after as Transform3D).is_equal_approx(expected),"Iori FX_Rotate identity child follows live parent transform")
  ck(before!=null and after!=null and not (before as Transform3D).is_equal_approx(after),"Iori reconstructed child cannot freeze animated parent")
  parent.free()
  ck(glue.resolve_live_anchor(iori_id,"Iori_Original/bone_root/FX_Rotate")==null,"missing Iori animated parent cannot fall back to actor root")
 ck(glue.resolve_live_anchor(iori_id,"Iori_Original/bone_root/Unproven_Anchor")==null,"unproven identity-like child is not guessed")
 glue.free()
 for view in views.values():view.free()
 print("EXPANDED_VFX_ANCHORS ",checks," checks; ",bound_paths," bound paths; ",failures," failures");quit(1 if failures else 0)
