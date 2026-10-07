extends Node3D
## Original shared HG hit textures, curves, burst delays and shader formulas.
## Spark damping/3D spawn orientation remain a Godot adaptation, not verified Unity parity.
static var _cached_profile:Dictionary={}
var born:=0.0
var lifetime:=0.36
var particles:Array=[]
var _visual_scale:=1.3
func begin(at:Vector3,time:float,seed_value:int,visual_scale:float=1.3)->void:
	born=time;global_position=at;_visual_scale=visual_scale
	if _cached_profile.is_empty():_cached_profile=JSON.parse_string(FileAccess.get_file_as_string("res://data/native-hg-impact.json"))
	var profile:Dictionary=_cached_profile
	var rng:=RandomNumberGenerator.new();rng.seed=seed_value
	for layer in profile.layers:
		if not layer.renderer.m_Enabled:continue
		var p:Dictionary=layer.particle
		var modules:Dictionary=p.activeModules
		if not modules.has("EmissionModule"):continue
		var burst:Dictionary=modules.EmissionModule.m_Bursts[0]
		var is_spark:bool=layer.name=="Muzzle"
		var count:=rng.randi_range(1,2) if is_spark else 1
		for n in range(count):
			var initial:Dictionary=p.initial
			var item:=MeshInstance3D.new();add_child(item)
			item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var quad:=QuadMesh.new();item.mesh=quad
			var material:=ShaderMaterial.new()
			material.shader=load("res://shaders/native_hit_spark.gdshader" if is_spark else "res://shaders/native_hit_step.gdshader")
			var props:Dictionary=layer.materials[0].props
			var colors:Dictionary={}
			for pair in props.m_Colors:colors[pair[0]]=pair[1]
			material.set_shader_parameter("material_intensity",float(colors._Color.r))
			var c:Dictionary=initial.startColor.maxColor
			material.set_shader_parameter("particle_tint",Vector3(c.r,c.g,c.b))
			if is_spark:material.set_shader_parameter("spark_texture",load("res://assets/native/fx/HG_Hit_Spark.png"))
			else:
				material.set_shader_parameter("mask_texture",load("res://assets/native/fx/HG_Hit_Ring.png" if layer.name=="Crash_HG" else "res://assets/native/fx/HG_Hit_Star.png"))
				material.set_shader_parameter("roll",_sample(initial.startRotation,0.0,rng.randf())+PI)
			var size:=_sample(initial.startSize,0.0,rng.randf())*0.27*visual_scale
			var life:=_sample(initial.startLifetime,0.0,rng.randf())
			var angle:=rng.randf()*TAU
			var direction:=Vector3(cos(angle)*sin(deg_to_rad(35.0)),cos(deg_to_rad(35.0)),sin(angle)*sin(deg_to_rad(35.0))).normalized()
			item.material_override=material;item.visible=false
			particles.append({"node":item,"quad":quad,"material":material,"delay":float(burst.time),"life":life,"size":size,"modules":modules,"spark":is_spark,"direction":direction,"speed":_sample(initial.startSpeed,0.0,rng.randf()),"offset":Vector3(cos(angle),0,sin(angle))*0.12*0.27*visual_scale if is_spark else Vector3.ZERO})
			lifetime=maxf(lifetime,float(burst.time)+life)
func update_time(now:float)->void:
	for p in particles:
		var age:float=now-born-p.delay
		p.node.visible=age>=0.0 and age<p.life
		if not p.node.visible:continue
		var t:float=clampf(age/p.life,0.0,1.0)
		var size_factor:=_sample(p.modules.SizeModule.curve,t,0.0)
		if p.spark:
			# Source limit velocity=1,dampen=.7. Explicit fixed-rate equivalent approximation.
			var decay:float=-log(1.0-0.7)*60.0
			var distance:float=age+(p.speed-1.0)*(1.0-exp(-decay*age))/decay
			p.node.position=p.offset+p.direction*distance*0.27*_visual_scale+Vector3.DOWN*0.5*9.81*0.2*age*age
			var y_factor:=_sample(p.modules.SizeModule.y,t,0.0)
			p.quad.size=Vector2(p.size*size_factor,p.size*y_factor*4.0)
			p.material.set_shader_parameter("direction",p.direction)
		else:
			p.quad.size=Vector2.ONE*p.size*size_factor
			p.material.set_shader_parameter("threshold",_sample(p.modules.CustomDataModule.vector0_0,t,0.0))
			p.material.set_shader_parameter("depth_offset",0.3*p.size if p.delay>0.0 else 0.0)
func visible_layers()->int:
	var total:=0
	for p in particles:
		if p.node.visible:total+=1
	return total
static func _sample(curve:Dictionary,t:float,random_fraction:float)->float:
	var mode:int=int(curve.minMaxState)
	if mode==0:return float(curve.scalar)
	if mode==3:return lerpf(float(curve.minScalar),float(curve.scalar),random_fraction)
	var points:Array=curve.maxCurve.m_Curve
	if points.is_empty():return float(curve.scalar)
	if t<=float(points[0].time):return float(points[0].value)*float(curve.scalar)
	for i in range(1,points.size()):
		var a:Dictionary=points[i-1];var b:Dictionary=points[i]
		if t<=float(b.time):
			var span:=float(b.time)-float(a.time)
			var u:float=(t-float(a.time))/span
			return float(curve.scalar)*((2*u*u*u-3*u*u+1)*a.value+(u*u*u-2*u*u+u)*span*a.outSlope+(-2*u*u*u+3*u*u)*b.value+(u*u*u-u*u)*span*b.inSlope)
	return float(points[-1].value)*float(curve.scalar)
