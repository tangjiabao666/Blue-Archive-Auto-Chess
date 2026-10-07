extends SceneTree
## Explicit support boundary and pool reuse using a real native source mesh layer.
const Player=preload("res://vfx/native_effect_player.gd")
const Source=preload("res://vfx/native_source.gd")
const FILE="res://data/effects/iori/visual-templates.json"
const PREFAB="FX_Iori_Original_Ex01_Motion_Start"
var checks:=0
var failures:=0
var base_node:Dictionary
var descriptor:Dictionary
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func anchor(_b:Dictionary,_e:Dictionary,_t:float)->Transform3D:return Transform3D.IDENTITY
func _initialize()->void:call_deferred("run")
func spawn_one(player,flip:Variant,mode:int=4,cull:int=0,pivot:Vector3=Vector3.ZERO)->void:
 var node:Dictionary=base_node.duplicate(true)
 node.hierarchy="test/native_mesh";node.name="native_mesh"
 var key:String="native_mesh_flip_test_cull_"+str(cull)
 for c in node.components:
  if c.type=="ParticleSystemRenderer":
   c.nativeParameters.m_RenderMode=mode
   c.nativeParameters.m_Pivot={"x":pivot.x,"y":pivot.y,"z":pivot.z}
   if flip==null:c.nativeParameters.erase("m_Flip")
   else:c.nativeParameters.m_Flip={"x":flip.x,"y":flip.y,"z":flip.z}
   c.materials=[{"materialKey":key}]
 var material:Dictionary=descriptor.duplicate(true);material.floats._Cull_Mode=cull
 var data:Dictionary={"materials":{key:material}}
 var prefab:Dictionary={"name":"native_test","nodes":[node]}
 var event:Dictionary={"start":0.0,"duration":1.0,"speed":1.0,"clipIn":0.0,"particleRandomSeed":7390,"bindings":[]}
 player._spawn_event(7,data,prefab,"res://data/effects",event,0.0,anchor)
 player.update_time(0.26)
func issue(player,code:String)->bool:
 for value in player.diagnostics().issues:
  if value.code==code:return true
 return false
func run()->void:
 var source:Dictionary=Source.read_json(FILE)
 for node in Source.find_prefab(source,PREFAB).nodes:
  if node.name=="stretch_line (9)":base_node=node;break
 for c in base_node.components:
  if c.type=="ParticleSystemRenderer":descriptor=source.materials[c.materials[0].materialKey]
 var control=Player.new();root.add_child(control);spawn_one(control,Vector3.ZERO)
 var baseline:Dictionary=control._effects[0].layers[0].particles[0]
 var baseline_transform:Transform3D=baseline.node.global_transform
 var mesh_bytes:PackedByteArray=var_to_bytes(baseline.node.mesh.surface_get_arrays(0))
 var sample_bytes:PackedByteArray=var_to_bytes(baseline.sample)
 var cases:Array=[
  [Vector3(1,0,0),4,0,Vector3(-1,1,1)],
  [Vector3(0,1,0),4,0,Vector3(1,-1,1)],
  [Vector3(0,0,1),4,0,Vector3(1,1,-1)],
  [Vector3(1,1,0),4,0,Vector3(-1,-1,1)],
  [Vector3(1,1,1),4,0,Vector3(-1,-1,-1)],
  [Vector3.ZERO,4,0,Vector3.ONE],
  [null,4,0,Vector3.ONE],
  [Vector3(0.5,0,0),4,0,Vector3.ONE],
  [Vector3(1,0.5,0),4,0,Vector3.ONE],
  [Vector3(-1,0,0),4,0,Vector3.ONE],
  [Vector3(2,0,0),4,0,Vector3.ONE],
  [Vector3(1,0,0),4,1,Vector3.ONE],
  [Vector3(1,0,0),4,2,Vector3.ONE],
  [Vector3(1,0,0),0,0,Vector3.ONE],
  [Vector3(1,0,0),1,0,Vector3.ONE]
 ]
 for c in cases:
  var player=Player.new();root.add_child(player);spawn_one(player,c[0],c[1],c[2])
  var layer:Dictionary=player._effects[0].layers[0]
  var item:Dictionary=layer.particles[0]
  var sign_vector:Vector3=c[3]
  var nonzero:bool=c[0]!=null and c[0]!=Vector3.ZERO
  ck(issue(player,"unsupported_renderer_flip")==bool(nonzero and sign_vector==Vector3.ONE),"only unsupported nonzero flips retain diagnostic "+str(c))
  ck(var_to_bytes(item.sample)==sample_bytes,"no RNG changes "+str(c))
  if c[1]==4:
   var expected:Transform3D=baseline_transform
   if sign_vector!=Vector3.ONE:expected.basis=expected.basis.scaled_local(sign_vector)
   ck(var_to_bytes(item.node.global_transform)==var_to_bytes(expected),"exact local reflection transform "+str(c))
   ck(var_to_bytes(item.node.mesh.surface_get_arrays(0))==mesh_bytes,"vertices/normals/indices/UV buffers untouched "+str(c))
   var arrays:Array=item.node.mesh.surface_get_arrays(0)
   var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
   var e1:Vector3=verts[indices[1]]-verts[indices[0]];var e2:Vector3=verts[indices[2]]-verts[indices[0]]
   var basis:Basis=item.node.global_basis
   ck((basis*e1).cross(basis*e2).is_equal_approx(basis.determinant()*(basis.inverse().transposed()*e1.cross(e2))),"winding follows determinant without index compensation "+str(c))
  if sign_vector!=Vector3.ONE:
   player.release(7);spawn_one(player,Vector3.ZERO)
   ck(player.diagnostics().nodes_reused==1,"source mesh visual reused")
   ck(var_to_bytes(player._effects[0].layers[0].particles[0].node.global_transform)==var_to_bytes(baseline_transform),"pooled zero flip clears prior reflection")
  player.free()
 var pivot_player=Player.new();root.add_child(pivot_player);spawn_one(pivot_player,Vector3(1,0,0),4,0,Vector3(0,0.3,0))
 ck(issue(pivot_player,"unsupported_renderer_pivot"),"flip support never suppresses unsupported pivot")
 ck(not issue(pivot_player,"unsupported_renderer_flip"),"supported flip remains independent of unsupported pivot")
 pivot_player.free();control.free()
 print("NATIVE_MESH_FLIP_SUPPORT checks=",checks," failures=",failures)
 quit(1 if failures else 0)
