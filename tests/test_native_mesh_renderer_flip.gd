extends SceneTree
## Native Iori source vs zero-flip control, including reversed seeks/negative anchors.
const Player=preload("res://vfx/native_effect_player.gd")
const Source=preload("res://vfx/native_source.gd")
const FILE="res://data/effects/iori/visual-templates.json"
const PREFAB="FX_Iori_Original_Ex01_Motion_Start"
var failures:=0
var checks:=0
var anchor_basis:=Basis.IDENTITY
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func anchor(_b:Dictionary,_e:Dictionary,_t:float)->Transform3D:return Transform3D(anchor_basis,Vector3(2,1,3))
func _initialize()->void:call_deferred("run")
func run()->void:
 var data:Dictionary=Source.read_json(FILE)
 var source:Dictionary=Source.find_prefab(data,PREFAB)
 var no_flip:Dictionary=source.duplicate(true)
 for node in no_flip.nodes:
  for c in node.components:
   if c.type=="ParticleSystemRenderer":c.nativeParameters["m_Flip"]={"x":0.0,"y":0.0,"z":0.0}
 var actual=Player.new();var control=Player.new();root.add_child(actual);root.add_child(control)
 var event:Dictionary={"start":0.0,"duration":1.0,"speed":1.0,"clipIn":0.0,"particleRandomSeed":7390,"bindings":[]}
 actual._spawn_event(1,data,source,"res://data/effects",event,0.0,anchor)
 control._spawn_event(1,data,no_flip,"res://data/effects",event,0.0,anchor)
 var source_bytes:PackedByteArray=var_to_bytes(source)
 for negative in [false,true]:
  anchor_basis=Basis.from_euler(Vector3(0.17,0.4,-0.3)).scaled_local(Vector3(-1 if negative else 1,2,0.7))
  for at in [0.0,0.149,0.26,0.4,0.7,0.26,0.26,-0.01,0.26]:
   actual.update_time(at);control.update_time(at)
   for li in actual._effects[0].layers.size():
    var a:Dictionary=actual._effects[0].layers[li];var b:Dictionary=control._effects[0].layers[li]
    for pi in a.particles.size():
     var ai:Dictionary=a.particles[pi];var bi:Dictionary=b.particles[pi]
     ck(var_to_bytes(ai.sample)==var_to_bytes(bi.sample),"flip consumes no particle RNG "+a.path)
     ck(ai.node.visible==bi.node.visible,"same scheduled visibility "+a.path)
     if not actual._effects[0].node.visible or not ai.node.visible:continue
     var atx:Transform3D=ai.node.global_transform;var btx:Transform3D=bi.node.global_transform
     for parameter in ["particle_color","custom0","custom1","uv_sheet","effect_time","roll"]:
      ck(ai.material.get_shader_parameter(parameter)==bi.material.get_shader_parameter(parameter),"unchanged source shader values "+parameter)
     ck(is_same(ai.node.mesh,bi.node.mesh),"mesh buffer reused without mutation")
     ck(ai.node.sorting_offset==bi.node.sorting_offset and ai.material.render_priority==bi.material.render_priority,"unchanged sorting and queue")
     var authored:Dictionary=a.render.get("m_Flip",{})
     if Vector3(float(authored.get("x",0)),float(authored.get("y",0)),float(authored.get("z",0)))==Vector3.ZERO:
      ck(var_to_bytes(atx)==var_to_bytes(btx),"zero-flip transforms remain byte-identical")
     if not a.path.ends_with("/stretch_line (9)"):
      continue
     ck(atx.origin==btx.origin,"reflection does not move source particle center")
     ck(atx.basis.y==btx.basis.y and atx.basis.z==btx.basis.z,"non-flipped native axes unchanged")
     ck(atx.basis.x==-btx.basis.x,"Iori native flip X=1 reflects local mesh X; negative anchor="+str(negative)+" time="+str(at))
     ck(is_equal_approx(atx.basis.determinant(),-btx.basis.determinant()),"odd flip changes determinant even with negative anchor")
     var arrays:Array=ai.node.mesh.surface_get_arrays(0)
     var pos:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
     var normal:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
     var expected_basis:Basis=btx.basis.scaled_local(Vector3(-1,1,1))
     ck((atx*pos[0]).is_equal_approx(btx*Vector3(-pos[0].x,pos[0].y,pos[0].z)),"actual native vertex reflection, not UV-only")
     ck((atx.basis.inverse().transposed()*normal[0]).is_equal_approx(expected_basis.inverse().transposed()*normal[0]),"reflected inverse-transpose native normal")
 ck(var_to_bytes(source)==source_bytes,"canonical loaded source remains byte-identical")
 actual.free();control.free()
 print("NATIVE_MESH_RENDERER_FLIP checks=",checks," failures=",failures)
 quit(1 if failures else 0)
