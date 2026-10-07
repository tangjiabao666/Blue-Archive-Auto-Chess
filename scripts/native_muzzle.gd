extends MeshInstance3D
## Recovered FX_Muzzle_HG: one stationary billboard, native curve/tint/atlas/lifetime.
static var _cached_profile:Dictionary={}
var lifetime := 0.1
var born := 0.0
var _size := 0.0
var _start_frame := 0.0
var _profile: Dictionary
var _shader: ShaderMaterial
var _quad: QuadMesh
func begin(anchor: Transform3D, at: float, seed_value: int, visual_scale: float = 1.3) -> void:
	if _cached_profile.is_empty():_cached_profile=JSON.parse_string(FileAccess.get_file_as_string("res://data/native-hg-muzzle.json"))
	_profile=_cached_profile
	var initial: Dictionary=_profile.InitialModule
	lifetime=float(initial.startLifetime.scalar)
	born=at
	var rng:=RandomNumberGenerator.new();rng.seed=seed_value
	_size=lerpf(float(initial.startSize.minScalar),float(initial.startSize.scalar),rng.randf())*visual_scale
	_start_frame=rng.randf()*0.75
	_quad=QuadMesh.new();_quad.size=Vector2.ONE*_size;mesh=_quad
	_shader=ShaderMaterial.new();_shader.shader=load("res://shaders/native_muzzle.gdshader")
	_shader.set_shader_parameter("atlas",load("res://assets/native/fx/HG_Muzzle.png"))
	_shader.set_shader_parameter("roll",rng.randf()*TAU)
	material_override=_shader
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_position=anchor.origin+anchor.basis.z.normalized()*0.05*visual_scale
	visible=false
func update_time(now: float) -> void:
	var age:=now-born
	visible=age>=0.0 and age<lifetime
	if not visible:return
	var t:=clampf(age/lifetime,0.0,1.0)
	var curve: Array=_profile.SizeModule.curve.maxCurve.m_Curve
	var a: Dictionary=curve[0];var b: Dictionary=curve[1]
	var span:=float(b.time)-float(a.time)
	var u:=clampf((t-float(a.time))/span,0.0,1.0)
	var size_factor: float=(2*u*u*u-3*u*u+1)*a.value+(u*u*u-2*u*u+u)*span*a.outSlope+(-2*u*u*u+3*u*u)*b.value+(u*u*u-u*u)*span*b.inSlope
	_quad.size=Vector2.ONE*_size*size_factor
	var gradient: Dictionary=_profile.ColorModule.gradient.maxGradient
	var fraction:=clampf(t/(float(gradient.ctime1)/65535.0),0.0,1.0)
	var c0:=Vector3(gradient.key0.r,gradient.key0.g,gradient.key0.b)
	var c1:=Vector3(gradient.key1.r,gradient.key1.g,gradient.key1.b)
	_shader.set_shader_parameter("particle_tint",c0.lerp(c1,fraction))
	_shader.set_shader_parameter("frame_index",float(int(floor(_start_frame*4.0+t))%4))
