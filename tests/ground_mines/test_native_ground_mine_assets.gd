extends SceneTree
const Mines=preload("res://scripts/native_ground_mines.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Mines.ASSET_DIR+"manifest.json"))
 var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Mines.ASSET_DIR+"runtime-metadata.json"))
 var materials:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Mines.ASSET_DIR+"material-bindings.json"))
 ck(FileAccess.get_sha256(Mines.MODEL)==manifest.glb_sha256,"delivered GLB is byte-identical to verified source conversion")
 ck(metadata.model_sha256==manifest.glb_sha256,"runtime provenance identifies the exact delivered GLB")
 ck(metadata.classification==Mines.CLASSIFICATION and not metadata.mutsuki_runtime_association_verified,"no false character-specific ownership claim")
 ck(manifest.meshes.size()==1 and manifest.meshes[0].vertices==900 and manifest.meshes[0].triangles==966,"real recovered mine geometry documented")
 ck(metadata.glb_contains_source_node_transform and not metadata.glb_contains_particle_initial_size_rotation_pivot,"source emitter transform distinguished from unbaked particle settings")
 var packed:PackedScene=load(Mines.MODEL)
 ck(packed!=null,"real mine GLB imports as PackedScene")
 var unmodified:Node3D=packed.instantiate()
 var source_meshes:Array=unmodified.find_children("*","MeshInstance3D",true,false)
 ck(source_meshes.size()==1,"one recovered mesh instance imports")
 if not source_meshes.is_empty():
  var mesh:MeshInstance3D=source_meshes[0]
  ck(mesh.mesh.get_surface_count()==1,"original opaque source material surface")
  var arrays:Array=mesh.mesh.surface_get_arrays(0)
  ck(arrays[Mesh.ARRAY_VERTEX].size()==900,"all 900 source vertices retained")
  ck(arrays[Mesh.ARRAY_INDEX].size()/3==966,"all 966 source triangles retained")
  ck(mesh.mesh.surface_get_material(0).resource_name=="Common_Skill_Landmine","native material name retained")
  ck((mesh.basis*Vector3.UP).is_equal_approx(Vector3(0,0,-1)),"source minus-90-degree emitter transform already imported once")
 unmodified.free()
 var mines:=Mines.new();root.add_child(mines);mines.configure({"mutsuki":{"model_scale":1.3}});mines.reset(31)
 var units:Array=[{"id":4,"character_id":"mutsuki","team":0},{"id":9,"character_id":"mutsuki","team":1}]
 for row in [{"id":0,"actor":4,"cell":Vector2(2,3)},{"id":1,"actor":9,"cell":Vector2(-2,-3)}]:
  mines.consume({"type":"mine_placed","mine_id":row.id,"actor_id":row.actor,"tick":0,"expires_tick":100,"generation":31,"event_id":"asset:%s"%row.id,"cell":row.cell},units)
 mines.update_time(0)
 ck(mines.diagnostics().active_mines==2,"both teams render real mines")
 ck(mines.diagnostics().issues.is_empty(),"all source resources map without fallback issues")
 var shared:Material
 for item in mines._active.values():
  var mesh:MeshInstance3D=item.model.find_children("*","MeshInstance3D",true,false)[0]
  var material:ShaderMaterial=mesh.get_active_material(0)
  ck(material is ShaderMaterial and material.shader.resource_path=="res://shaders/native_weapon.gdshader","recovered MX/C-Weapon family uses native shader adapter")
  if shared!=null:ck(shared==material,"instances share warmed immutable native materials")
  shared=material
  ck(material.next_pass is ShaderMaterial and material.next_pass.shader.resource_path=="res://shaders/native_outline.gdshader","verified source weapon outline pass mapped")
  ck(material.get_shader_parameter("glow_enabled")==true,"native glow keyword preserved")
  ck(is_equal_approx(float(material.get_shader_parameter("glow_strength0")),0.5),"native glow strength preserved")
  ck(is_equal_approx(float(material.get_shader_parameter("shadow_threshold")),0.6899999976158142),"native shadow threshold preserved")
  ck(is_equal_approx(float(material.get_shader_parameter("light_value")),0.5),"native light value preserved")
  ck(is_equal_approx(float(material.get_shader_parameter("spec_strong")),0.019999999552965164),"native specular strength preserved")
  ck((material.get_shader_parameter("glow_tint0") as Vector3).is_equal_approx(Vector3(6.498019218444824,0,0)),"native HDR glow tint preserved")
  for key in ["main_texture","source_texture"]:
   var texture:Texture2D=material.get_shader_parameter(key)
   ck(texture!=null and texture.get_size()==Vector2(64,64),"exact native 64px texture loaded: "+key)
   if texture!=null:
    var source:Image=Image.load_from_file(ProjectSettings.globalize_path(texture.resource_path))
    var imported:Image=texture.get_image()
    if imported.is_compressed():imported.decompress()
    source.convert(Image.FORMAT_RGBA8);imported.convert(Image.FORMAT_RGBA8)
    ck(source.get_data()==imported.get_data(),"imported native texture pixels preserved: "+key)
  var pose:Basis=item.model.basis*mesh.basis
  ck(pose.orthonormalized().is_equal_approx(Basis.IDENTITY),"source-derived static pose cancels emitter rotation once")
  ck(pose.get_scale().is_equal_approx(Vector3.ONE*2.2*1.3),"native size times uniform world scale is applied once")
 for binding in materials.materials:
  for path in binding.textures.values():ck(ResourceLoader.exists(path),"packed texture dependency available: "+str(path))
 for file in ["runtime-metadata.json","material-bindings.json","manifest.json","texture-manifest.json","visibility-manifest.json","source_materials/Common_Skill_Landmine.json","source_objects/ParticleSystem_-316257676384098398.json"]:
  ck(FileAccess.file_exists(Mines.ASSET_DIR+file),"provenance dependency: "+file)
 mines.reset(32);ck(mines.get_child_count()==0,"asset reset removes both teams without hidden resources")
 mines.free()
 print("NATIVE_GROUND_MINE_ASSETS ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
