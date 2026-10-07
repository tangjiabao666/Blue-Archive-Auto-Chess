extends MeshInstance3D
## Preparation-only visualization. Uses the simulation's radius, never applies damage.
const SEGMENTS := 128
const WIDTH := 0.035
var radius := 0.0
func configure(attack_range: float) -> void:
	assert(is_finite(attack_range) and attack_range>WIDTH)
	radius=attack_range
	var vertices:=PackedVector3Array()
	for i in range(SEGMENTS):
		var a:=TAU*float(i)/SEGMENTS
		var b:=TAU*float(i+1)/SEGMENTS
		var outer_a:=Vector3(cos(a),0,sin(a))*radius
		var inner_a:=Vector3(cos(a),0,sin(a))*(radius-WIDTH)
		var outer_b:=Vector3(cos(b),0,sin(b))*radius
		var inner_b:=Vector3(cos(b),0,sin(b))*(radius-WIDTH)
		vertices.append_array(PackedVector3Array([outer_a,inner_a,outer_b,outer_b,inner_a,inner_b]))
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	var ring:=ArrayMesh.new()
	ring.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh=ring
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.albedo_color=Color(0.65,0.85,1.0,0.48)
	material_override=material
	position.y=0.035
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible=false
