extends SceneTree
const Glue=preload("res://scripts/native_combat_vfx.gd")
const View=preload("res://scripts/unit_view.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize():call_deferred("run")
func run():
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 var view=View.new();root.add_child(view)
 view.setup({"id":0,"character_id":"asuna","team":0,"cell":Vector2.ZERO,"range":6.5,"attack_ticks":43,"presentation":profiles.asuna},{},1)
 var glue=Glue.new();root.add_child(glue)
 glue._profiles=profiles;glue._views={0:view};glue._characters={0:"asuna"};glue._source_roots={"asuna":"Asuna_Original"};glue._indices[0]=glue._index_view(view)
 var sources:Array=glue._muzzle_sources("asuna")
 ck(sources.size()==1,"one exact muzzle")
 ck(sources[0].path=="Asuna_Original/bone_root/Bip001/Bip001_Weapon/fire_01","rooted muzzle path is not doubled")
 ck(sources[0].parent=="Asuna_Original/bone_root/Bip001/Bip001_Weapon","rooted muzzle parent is not doubled")
 var weapon_path:="Asuna_Original/bone_root/Bip001/Bip001_Weapon"
 ck(glue.resolve_live_anchor(0,weapon_path) is Transform3D,"weapon BoneAttachment aliases the live skeletal identity")
 var skeleton:Skeleton3D=view._anchor_skeleton
 var bone:int=skeleton.find_bone("Bip001_Weapon")
 var fire_nodes:Dictionary={}
 for leaf in ["fire_01","fire_02"]:
  var candidates:Array=view._model.find_children(leaf,"Node3D",true,false)
  ck(candidates.size()==1,"one imported "+leaf)
  fire_nodes[leaf]=candidates[0]
 for row in [["idle",0.3],["attack_fire",0.2],["reload",0.9],["ex",1.2]]:
  view.player.play(profiles.asuna.clips[row[0]],0.0);view.player.seek(row[1],true);view.player.advance(0.0);view.player.pause()
  for leaf in ["fire_01","fire_02"]:
   var actual=glue.resolve_live_anchor(0,weapon_path+"/"+leaf)
   var expected:Transform3D=glue._bridge(skeleton.global_transform*skeleton.get_bone_global_pose(bone)*fire_nodes[leaf].transform)
   ck(actual is Transform3D and (actual as Transform3D).is_equal_approx(expected),"same-tick bone + animated "+leaf+" local: "+str(row[0]))
  ck(glue._live_muzzle(0) is Transform3D and (glue._live_muzzle(0) as Transform3D).is_equal_approx(glue._bridge(view.muzzle_transform())),"muzzle equals UnitView same-tick socket: "+str(row[0]))
 # The successful cache must still read changed authored descendant transforms.
 var original:Transform3D=fire_nodes.fire_02.transform
 fire_nodes.fire_02.position+=Vector3(.25,.5,-.75)
 var changed=glue.resolve_live_anchor(0,weapon_path+"/fire_02")
 ck(changed is Transform3D and (changed as Transform3D).is_equal_approx(glue._bridge(skeleton.global_transform*skeleton.get_bone_global_pose(bone)*fire_nodes.fire_02.transform)),"cached descendant reads changed local immediately")
 fire_nodes.fire_02.transform=original
 # A genuinely distinct same-named node remains ambiguous after reindexing.
 var duplicate:=Node3D.new();duplicate.name="Bip001_Weapon";view._model.add_child(duplicate)
 glue._indices[0]=glue._index_view(view)
 ck(glue.resolve_live_anchor(0,weapon_path)==null,"distinct weapon node remains ambiguous")
 duplicate.free();glue._indices[0]=glue._index_view(view)
 ck(glue.resolve_live_anchor(0,weapon_path) is Transform3D,"reindex resolves after true ambiguity removed")
 glue.resolve_live_anchor(0,weapon_path+"/fire_02")
 fire_nodes.fire_02.free()
 ck(glue.resolve_live_anchor(0,weapon_path+"/fire_02")==null,"freed cached descendant fails closed")
 ck(glue.resolve_live_anchor(0,"Foreign/fire_01")==null,"foreign root fails closed")
 # Existing characters keep the legacy direct-node and ambiguous alias branch.
 var compact:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Glue.EVENTS))
 for character in compact.activeRoster:
  if character=="asuna":continue # Asuna canonical branch is checked separately above.
  glue._characters[0]=character;glue._source_roots[character]="Asuna_Original";glue._indices[0]=glue._index_view(view)
  ck(glue.resolve_live_anchor(0,weapon_path)==null,"legacy ambiguous alias unchanged for "+character)
  ck((glue.resolve_live_anchor(0,weapon_path+"/fire_01") as Transform3D).is_equal_approx(glue._bridge(fire_nodes.fire_01.global_transform)),"legacy direct descendant unchanged for "+character)
 view.free();glue.free()
 print("ASUNA LIVE BINDINGS CHECKS=",checks," FAILURES=",failures);quit(1 if failures else 0)
