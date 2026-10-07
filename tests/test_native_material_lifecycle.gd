extends SceneTree
## Native override ownership must span child renderer destruction, without leaks.
const Adapter=preload("res://scripts/native_material_adapter.gd")
class DestructionSentinel extends Node:
	var expected:Array=[]
	var result:Dictionary={}
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			result.alive=true
			for ref in expected:
				if ref.get_ref()==null:result.alive=false
var checks:=0
var failures:=0
func ck(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:call_deferred("run")
func _snapshot(material:Material)->Dictionary:
	var result:Dictionary={"type":material.get_class(),"priority":material.render_priority}
	if material is ShaderMaterial:
		result.shader=material.shader
		var values:Dictionary={}
		for uniform in material.shader.get_shader_uniform_list():
			values[uniform.name]=material.get_shader_parameter(uniform.name)
		result.values=values
	else:result.color=material.albedo_color
	if material.next_pass:result.next_pass=_snapshot(material.next_pass)
	return result
func _references(model:Node3D)->Array:
	var result:Array=[]
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var material:Material=mesh.get_surface_override_material(0)
		result.append(weakref(material))
		if material.next_pass:result.append(weakref(material.next_pass))
	return result
func _add_mesh(model:Node3D,material_name:String)->void:
	var mesh:=MeshInstance3D.new();var geometry:=BoxMesh.new()
	var original:=StandardMaterial3D.new();original.resource_name=material_name
	geometry.material=original;mesh.mesh=geometry;model.add_child(mesh)
func run()->void:
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	var records:Array=profiles.shiroko.materials
	var model:=Node3D.new();root.add_child(model)
	for record in records:_add_mesh(model,record.name)
	_add_mesh(model,records[0].name)
	Adapter.apply(model,records)
	ck(model.get_meta("_native_material_keepalive",[]).size()==records.size(),"shared material is retained once")
	var snapshots:Array=[]
	for mesh in model.get_children():snapshots.append(_snapshot(mesh.get_surface_override_material(0)))
	var old_refs:Array=_references(model)
	for iteration in 3:
		Adapter.apply(model,records)
		for ref in old_refs:ck(ref.get_ref()==null,"reapply releases superseded material/pass")
		for index in model.get_child_count():ck(_snapshot(model.get_child(index).get_surface_override_material(0))==snapshots[index],"reapply preserves every shader value and outline")
		old_refs=_references(model)
	# A partial call leaves the remaining overrides in use: their ownership must survive.
	Adapter.apply(model,[records[0]])
	var active_refs:Array=_references(model)
	Adapter.apply(model,[])
	for ref in active_refs:ck(ref.get_ref()!=null,"empty reapply preserves active material/pass")
	# Destroy child renderer instances first. The model must still own their materials.
	for mesh in model.get_children():mesh.free()
	for ref in active_refs:ck(ref.get_ref()!=null,"model outlives child renderer material release")
	model.free()
	for ref in active_refs:ck(ref.get_ref()==null,"model deletion releases material/pass without a cycle")
	# Node destroys children in reverse order. The first-added sentinel runs
	# after both meshes, while their model parent is itself being destroyed.
	var automatic:=Node3D.new();root.add_child(automatic)
	var result:Dictionary={}
	var sentinel:=DestructionSentinel.new();sentinel.result=result;automatic.add_child(sentinel)
	_add_mesh(automatic,records[0].name);_add_mesh(automatic,records[1].name)
	Adapter.apply(automatic,records)
	var automatic_refs:Array=_references(automatic);sentinel.expected=automatic_refs
	automatic.free()
	ck(result.get("alive",false),"parent ownership survives automatic child destruction order")
	for ref in automatic_refs:ck(ref.get_ref()==null,"automatic parent deletion releases retained material/pass")
	await process_frame
	print("NATIVE MATERIAL LIFECYCLE CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
