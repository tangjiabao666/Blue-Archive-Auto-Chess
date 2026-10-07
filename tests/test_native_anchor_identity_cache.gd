extends SceneTree
## Identity caches may skip lookups, never live transforms or contact captures.
const Glue=preload("res://scripts/native_combat_vfx.gd")
const Props=preload("res://scripts/native_skill_props.gd")
var checks:=0
var failures:=0
class View extends Node3D:
 var _model:Node3D
 func hit_position()->Vector3:return global_position+Vector3.UP
class CountingGlue extends "res://scripts/native_combat_vfx.gd":
 var resolutions:=0
 var identity_lookups:=0
 func _bind_live_anchor(index:Dictionary,character:String,path:String)->Array:
  identity_lookups+=1
  return super._bind_live_anchor(index,character,path)
 func resolve_live_anchor(actor:int,path:String):
  resolutions+=1
  return super.resolve_live_anchor(actor,path)
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func make_view()->View:
 var view:=View.new();root.add_child(view)
 view._model=Node3D.new();view._model.name="Model";view.add_child(view._model)
 view._model.transform=Transform3D(Basis.from_euler(Vector3(.1,.6,-.2)).scaled_local(Vector3(1.3,1.3,1.3)),Vector3(2,3,4))
 return view
func node(parent:Node3D,name:String,p:Vector3=Vector3.ZERO)->Node3D:
 var result:=Node3D.new();result.name=name;result.position=p;parent.add_child(result);return result
func run()->void:
 var view:=make_view()
 var socket:=node(view._model,"fire",Vector3(.1,.4,-.6))
 var parent:=node(view._model,"bone_root",Vector3(.2,.8,.1))
 var skeleton:=Skeleton3D.new();view._model.add_child(skeleton)
 skeleton.add_bone("bone_Calculator");skeleton.set_bone_pose_position(0,Vector3(.3,.2,.4))
 var glue:=CountingGlue.new();root.add_child(glue)
 glue._views={1:view};glue._characters={1:"iori"};glue._source_roots={"iori":"Iori_Original"}
 glue._profiles={"iori":{"muzzle_anchor":"fire","anchors":[{"name":"fire","path":"fire"}]}}
 glue._source_paths={"iori":["Iori_Original/fire","Iori_Original/bone_root/FX_Rotate","Iori_Original/bone_Calculator"]}
 glue._indices[1]=glue._index_view(view)
 glue._capture_history(0.0)
 ck(glue.resolutions==3,"capture reuses exact muzzle transform already sampled in this capture")
 ck(glue._indices[1].has("bindings") and glue._indices[1].get("bindings",{}).has("Iori_Original/fire"),"successful source path caches its node identity")
 var initial_lookups:int=glue.identity_lookups
 var first:Transform3D=glue._sample_anchor(1,"@muzzle",0)
 socket.position+=Vector3(1,.2,-.1);parent.position+=Vector3(.5,.1,.3)
 skeleton.set_bone_pose_position(0,Vector3(2,4,6))
 glue._capture_history(0.0)
 ck(glue.identity_lookups==initial_lookups,"warm capture performs no node-name or bone-name identity lookups")
 var sample:Dictionary=glue._history[1][-1].anchors
 ck(sample["@muzzle"]==Glue._bridge(socket.global_transform),"same-time capture reads changed live socket")
 ck(sample["@muzzle"]!=first,"identity caching never memoizes a pose")
 ck(sample["Iori_Original/bone_root/FX_Rotate"]==Glue._bridge(parent.global_transform),"Iori identity child inherits animated parent")
 ck(sample["Iori_Original/bone_Calculator"]==Glue._bridge(skeleton.global_transform*skeleton.get_bone_global_pose(0)),"bone binding reads current animated pose")
 ck(glue.resolve_live_anchor(1,"Foreign/fire")==null,"foreign roots cannot use matching cached leaves")
 var other:=make_view();var other_socket:=node(other._model,"fire",Vector3(-8,2,3))
 glue._views[2]=other;glue._characters[2]="iori";glue._indices[2]=glue._index_view(other)
 glue._capture_history(0.0,[2])
 ck(glue._sample_anchor(2,"@muzzle",0)==Glue._bridge(other_socket.global_transform),"same-character actors share socket metadata but retain separate live identities")
 ck(glue._sample_anchor(2,"@muzzle",0)!=glue._sample_anchor(1,"@muzzle",0),"same-character actor captures never reuse another actor's transform")
 glue._views.erase(2);glue._characters.erase(2);glue._indices.erase(2);other.free()
 # A miss or ambiguity is deliberately not cached. The existing roster index
 # may be repaired/replaced by its owner, without a stale negative binding.
 ck(glue.resolve_live_anchor(1,"Iori_Original/late")==null,"missing path remains missing")
 var late:=node(view._model,"late",Vector3(9,8,7));glue._indices[1].names["late"]=[late]
 ck(glue.resolve_live_anchor(1,"Iori_Original/late")==Glue._bridge(late.global_transform),"missing identity resolves lazily from repaired roster index")
 var duplicate:=node(view._model,"duplicate",Vector3(6,5,4))
 glue._indices[1].names["ambiguous"]=[late,duplicate]
 ck(glue.resolve_live_anchor(1,"Iori_Original/ambiguous")==null,"ambiguous identity is rejected")
 glue._indices[1].names["ambiguous"]=[late]
 ck(glue.resolve_live_anchor(1,"Iori_Original/ambiguous")==Glue._bridge(late.global_transform),"ambiguity is not permanently cached")
 # Instrument identity lookup cost by removing the immutable lookup table after
 # successful binding. Live transforms must remain available from the identity.
 glue._indices[1].names["fire"]=[]
 ck(glue.resolve_live_anchor(1,"Iori_Original/fire")==Glue._bridge(socket.global_transform),"warm successful identity requires no repeated name-table resolution")
 socket.free()
 ck(glue.resolve_live_anchor(1,"Iori_Original/fire")==null,"freed cached node cannot provide a stale transform")
 # Fresh model identity invalidates every old node and skeletal binding.
 var old_model:Node3D=view._model
 old_model.free()
 view._model=Node3D.new();view.add_child(view._model)
 var replacement:=node(view._model,"fire",Vector3(-2,-3,-4))
 ck(glue.resolve_live_anchor(1,"Iori_Original/fire")==Glue._bridge(replacement.global_transform),"model replacement invalidates the old roster index")
 # A reindexed roster also invalidates positives, even on the same model.
 glue._indices[1]=glue._index_view(view)
 ck(glue.resolve_live_anchor(1,"Iori_Original/fire")==Glue._bridge(replacement.global_transform),"explicit index rebuild provides fresh identities")
 # Authored local scale belongs to immutable socket data, while the parent is live.
 replacement.free();var live_parent:=node(view._model,"weapon",Vector3(1,2,3))
 glue._profiles["iori"]={"muzzle_anchor":"fire","anchors":[{"name":"fire","path":"weapon/fire","local_translation":[.1,.2,.3],"local_rotation":[0,0,0,1],"local_scale":[2,3,4]}]}
 glue.reset(2);glue._views={1:view};glue._characters={1:"iori"};glue._indices[1]=glue._index_view(view)
 var authored:=Transform3D(Basis.IDENTITY.scaled_local(Vector3(2,3,4)),Vector3(.1,.2,.3))
 ck(glue._live_muzzle(1)==Glue._bridge(live_parent.global_transform*authored),"ordinary-fire fallback preserves authored socket scale")
 live_parent.position+=Vector3(2,4,8)
 ck(glue._live_muzzle(1)==Glue._bridge(live_parent.global_transform*authored),"static socket reconstruction still follows current parent")
 ck(glue.resolve_live_anchor(1,"Iori_Original/weapon/fire")==null,"ordinary-fire fallback never invents an exact source anchor")
 live_parent.free();ck(glue._live_muzzle(1)==null,"missing socket parent cannot fall back to UnitView root")
 var configured:=node(view._model,"configured",Vector3(4,3,2))
 glue.configure({"iori":{"muzzle_anchor":"configured","anchors":[{"name":"configured","path":"configured"}]}})
 ck(glue._indices.is_empty() and glue._muzzle_bindings.is_empty(),"reconfigure clears identity and immutable socket metadata caches")
 ck(glue._live_muzzle(1)==Glue._bridge(configured.global_transform),"reconfigure uses the new muzzle profile")
 glue.reset(3);ck(glue._indices.is_empty(),"generation reset clears bound identities")
 var props:=Props.new();root.add_child(props);props._views={1:view};props._characters={1:"shiroko"}
 var ex:=node(view._model,"Ex_Root",Vector3(2,4,6))
 ck(props._live_anchor(1)==ex.global_transform,"prop captures exact Ex_Root")
 ck(props.get("_anchor_bindings") is Dictionary and props.get("_anchor_bindings").has(1),"prop captures bind Ex_Root identity once")
 ex.position+=Vector3(.3,.2,.1);ck(props._live_anchor(1)==ex.global_transform,"prop identity never freezes animated transform")
 ex.free();ck(props._live_anchor(1)==view._model.global_transform,"pruned prop uses only verified identity fallback")
 old_model=view._model;view._model=Node3D.new();view.add_child(view._model)
 ex=node(view._model,"Ex_Root",Vector3(-1,-2,-3));ck(props._live_anchor(1)==ex.global_transform,"prop model replacement invalidates fallback binding")
 old_model.free()
 props.configure({"shiroko":{}})
 ck(props._anchor_bindings.is_empty(),"prop reconfigure clears anchor bindings")
 var branch:=node(view._model,"branch");var ambiguous_ex:=node(branch,"Ex_Root")
 ck(props._live_anchor(1)==null,"ambiguous prop Ex_Root remains rejected")
 ambiguous_ex.free()
 ck(props._live_anchor(1)==ex.global_transform,"ambiguous prop identity remains lazily resolvable")
 props.reset(4)
 ck(props.get("_anchor_bindings") is Dictionary and props.get("_anchor_bindings").is_empty(),"prop generation reset clears anchor identities")
 props.free();glue.free();view.free()
 print("NATIVE_ANCHOR_IDENTITY_CACHE ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
