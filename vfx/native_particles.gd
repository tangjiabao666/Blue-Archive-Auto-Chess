extends RefCounted
const Curves = preload("native_curves.gd")
## Deterministic CPU schedules; source module values are never rewritten.
## RNG stream deliberately is Godot's seeded stream, not asserted Unity parity.
static func emit(p: Dictionary, seed_value: int, horizon: float, cap: int = 2048) -> Array:
 var emission: Dictionary = p.get("EmissionModule",{})
 if not emission.get("enabled",false): return []
 var rng := RandomNumberGenerator.new(); rng.seed=seed_value
 var duration: float = maxf(float(p.get("lengthInSec",5.0)),0.00001)
 var delay: float = Curves.sample(p.get("startDelay",{}),0.0,rng.randf())
 var speed: float = maxf(float(p.get("simulationSpeed",1.0)),0.00001)
 var end: float = maxf(0.0,horizon*speed-delay)
 var cycles: int = int(ceil(end/duration))+1 if p.get("looping",false) else 1
 var births: Array[float] = []
 for cycle in range(mini(cycles,4096)):
  var base: float = float(cycle)*duration
  if base>end:break
  for burst in emission.get("m_Bursts",[]):
   var count_cycles: int = int(burst.get("cycleCount",1))
   var interval: float = maxf(float(burst.get("repeatInterval",0.01)),0.00001)
   if count_cycles==0:count_cycles=int(ceil(duration/interval))
   for repeat in range(mini(count_cycles,cap)):
    var at: float = base+float(burst.get("time",0))+float(repeat)*interval
    if at>end or at>=base+duration:break
    if rng.randf()>float(burst.get("probability",1)):continue
    var count: int = maxi(0,int(round(Curves.sample(burst.get("countCurve",{}),(at-base)/duration,rng.randf()))))
    for j in range(mini(count,cap-births.size())): births.append(at)
  var rate: Dictionary = emission.get("rateOverTime",{})
  var local_end: float = minf(duration,end-base)
  if int(rate.get("minMaxState",0)) in [0,3]:
   var hz: float=Curves.sample(rate,0,rng.randf())
   if hz>0:
    for j in range(1,mini(int(floor(local_end*hz+0.0000001)),cap-births.size())+1):births.append(base+float(j)/hz)
  else:
   var dt: float = 1.0/120.0; var accumulated: float=0.0; var fraction: float=rng.randf()
   for step in range(int(ceil(local_end/dt))):
    var a: float=float(step)*dt; var b: float=minf(a+dt,local_end)
    accumulated+=(Curves.sample(rate,a/duration,fraction)+Curves.sample(rate,b/duration,fraction))*0.5*(b-a)
    while accumulated>=1.0 and births.size()<cap:
     births.append(base+b);accumulated-=1.0
  if births.size()>=cap:break
 births.sort()
 var initial: Dictionary=p.get("InitialModule",{})
 var result: Array=[]
 var living_ends: Array[float]=[]
 var native_cap: int=maxi(1,int(initial.get("maxNumParticles",1000)))
 for birth in births:
  var fractions: Array[float]=[]
  for k in range(24):fractions.append(rng.randf())
  var t: float=fposmod(birth,duration)/duration
  var life: float=maxf(0.000001,Curves.sample(initial.get("startLifetime",{}),t,fractions[0],5.0))
  for k in range(living_ends.size()-1,-1,-1):
   if living_ends[k]<=birth:living_ends.remove_at(k)
  if living_ends.size()>=native_cap:continue
  living_ends.append(birth+life)
  var shape: Dictionary=shape_sample(p.get("ShapeModule",{}),fractions)
  var size: float=Curves.sample(initial.get("startSize",{}),t,fractions[2],1.0)
  var sizes: Vector3=Vector3.ONE*size
  if initial.get("size3D",false):sizes=Vector3(size,Curves.sample(initial.get("startSizeY",{}),t,fractions[3],1.0),Curves.sample(initial.get("startSizeZ",{}),t,fractions[4],1.0))
  var rot: Vector3=Vector3(0,0,Curves.sample(initial.get("startRotation",{}),t,fractions[5]))
  if initial.get("rotation3D",false):rot.x=Curves.sample(initial.get("startRotationX",{}),t,fractions[6]);rot.y=Curves.sample(initial.get("startRotationY",{}),t,fractions[7])
  if fractions[8]<float(initial.get("randomizeRotationDirection",0)):rot=-rot
  result.append({"birth":(delay+birth)/speed,"life":life/speed,"native_life":life,"fractions":fractions,"size":sizes,"rotation":rot,"start_position":shape.position,"direction":shape.direction,"start_speed":Curves.sample(initial.get("startSpeed",{}),t,fractions[1]),"color":Curves.minmax_color(initial.get("startColor",{}),t,fractions[9]),"simulation_speed":speed,"gravity":Curves.sample(initial.get("gravityModifier",{}),t,fractions[10])})
 return result

static func shape_sample(shape: Dictionary,r: Array) -> Dictionary:
 var position:=Vector3.ZERO;var direction:=Vector3(0,0,1)
 if not shape.get("enabled",false):return {"position":position,"direction":Vector3.FORWARD}
 var type: int=int(shape.get("type",0));var radius: float=float(shape.get("radius",{}).get("value",1))
 var thickness: float=float(shape.get("radiusThickness",1));var angle: float=float(r[11])*deg_to_rad(float(shape.get("arc",{}).get("value",360)))
 var radial: float=radius*sqrt(lerpf(pow(1.0-thickness,2),1.0,float(r[12])))
 if type in [4,7,8,9,10,11]:
  position=Vector3(cos(angle)*radial,sin(angle)*radial,0)
  if type in [4,7,8,9]:
   var a: float=deg_to_rad(float(shape.get("angle",25)))
   direction=Vector3(cos(angle)*sin(a),sin(angle)*sin(a),cos(a))
   if type in [8,9]:position+=direction*float(r[13])*float(shape.get("length",1))
  elif type in [10,11]:direction=Vector3(cos(angle),sin(angle),0)
 elif type in [0,1,2,3]:
  var z: float=lerpf(-1,1,float(r[13])) if type in [0,1] else float(r[13])
  direction=Vector3(sqrt(maxf(0,1-z*z))*cos(angle),sqrt(maxf(0,1-z*z))*sin(angle),z)
  position=direction*radius*pow(lerpf(pow(1-thickness,3),1,float(r[12])),1.0/3.0)
 elif type in [5,15,16,18]:position=Vector3(float(r[11])-0.5,float(r[12])-0.5,0 if type==18 else float(r[13])-0.5)
 elif type==12:position=Vector3(lerpf(-radius,radius,float(r[11])),0,0)
 var scale_d: Dictionary=shape.get("m_Scale",{})
 position*=Vector3(float(scale_d.get("x",1)),float(scale_d.get("y",1)),float(scale_d.get("z",1)))
 var rot: Dictionary=shape.get("m_Rotation",{})
 var basis: Basis=Basis.from_euler(Vector3(deg_to_rad(float(rot.get("x",0))),deg_to_rad(float(rot.get("y",0))),deg_to_rad(float(rot.get("z",0)))),EULER_ORDER_YXZ)
 position=basis*position;direction=basis*direction
 var offset: Dictionary=shape.get("m_Position",{})
 position+=Vector3(float(offset.get("x",0)),float(offset.get("y",0)),float(offset.get("z",0)))
 position.z=-position.z;direction.z=-direction.z
 return {"position":position,"direction":direction.normalized()}

static func state(p: Dictionary, particle: Dictionary, local_time: float) -> Dictionary:
 var elapsed: float=local_time-float(particle.birth)
 if elapsed<0 or elapsed>=float(particle.life):return {"visible":false}
 var age: float=elapsed*float(particle.simulation_speed)
 var life: float=float(particle.native_life);var t: float=clampf(age/life,0,1)
 var r: Array=particle.fractions
 var position: Vector3=particle.start_position+particle.direction*float(particle.start_speed)*age
 var world_offset: Vector3=Vector3.DOWN*(0.5*9.81*float(particle.gravity)*age*age)
 var velocity: Dictionary=p.get("VelocityModule",{})
 if velocity.get("enabled",false):
  position+=Vector3(Curves.integral(velocity.get("x",{}),t,r[14]),Curves.integral(velocity.get("y",{}),t,r[15]),-Curves.integral(velocity.get("z",{}),t,r[16]))*life
 var force: Dictionary=p.get("ForceModule",{})
 if force.get("enabled",false):
  position+=Vector3(Curves.sample(force.get("x",{}),t,r[14]),Curves.sample(force.get("y",{}),t,r[15]),-Curves.sample(force.get("z",{}),t,r[16]))*age*age*0.5
 var size: Vector3=particle.size
 var sm: Dictionary=p.get("SizeModule",{})
 if sm.get("enabled",false):
  var sx: float=Curves.sample(sm.get("curve",{}),t,r[17],1)
  size*=Vector3(sx,Curves.sample(sm.get("y",{}),t,r[18],1),Curves.sample(sm.get("z",{}),t,r[19],1)) if sm.get("separateAxes",false) else Vector3.ONE*sx
 var rotation: Vector3=particle.rotation
 var rm: Dictionary=p.get("RotationModule",{})
 if rm.get("enabled",false):
  rotation.z+=Curves.integral(rm.get("curve",{}),t,r[20])*life
  if rm.get("separateAxes",false):rotation.x+=Curves.integral(rm.get("x",{}),t,r[21])*life;rotation.y+=Curves.integral(rm.get("y",{}),t,r[22])*life
 rotation.x=-rotation.x;rotation.y=-rotation.y
 var color: Color=particle.color
 var cm: Dictionary=p.get("ColorModule",{})
 if cm.get("enabled",false):color*=Curves.minmax_color(cm.get("gradient",{}),t,r[23])
 var cd: Dictionary=p.get("CustomDataModule",{})
 var custom0:=Vector4.ZERO;var custom1:=Vector4.ZERO
 if cd.get("enabled",false):
  if int(cd.get("mode0",0))==1:
   for i in range(4):custom0[i]=Curves.sample(cd.get("vector0_%d"%i,{}),t,r[20])
  elif int(cd.get("mode0",0))==2:
   var custom_color: Color=Curves.minmax_color(cd.get("color0",{}),t,r[20])
   custom0=Vector4(custom_color.r,custom_color.g,custom_color.b,custom_color.a)
  if int(cd.get("mode1",0))==1:
   for i in range(4):custom1[i]=Curves.sample(cd.get("vector1_%d"%i,{}),t,r[21])
  elif int(cd.get("mode1",0))==2:
   var custom_color: Color=Curves.minmax_color(cd.get("color1",{}),t,r[21])
   custom1=Vector4(custom_color.r,custom_color.g,custom_color.b,custom_color.a)
 return {"visible":true,"position":position,"world_offset":world_offset,"size":size,"rotation":rotation,"color":color,"custom0":custom0,"custom1":custom1,"uv_sheet":Curves.sheet(p.get("UVModule",{}),t,age,r[22]),"age":age,"normalized_age":t}

static func limitations(p: Dictionary) -> Array[String]:
 var result: Array[String]=[]
 var handled: Array[String]=["InitialModule","EmissionModule","ShapeModule","SizeModule","RotationModule","ColorModule","VelocityModule","CustomDataModule","UVModule"]
 for key in p:
  if key.ends_with("Module") and p[key] is Dictionary and p[key].get("enabled",false) and not handled.has(key):result.append("unsupported_module:"+key)
 var shape: Dictionary=p.get("ShapeModule",{})
 if shape.get("enabled",false):
  if not int(shape.get("type",0)) in [0,1,2,3,4,5,7,8,9,10,11,12,15,16,18]:result.append("unsupported_shape:%s"%shape.get("type"))
  if int(shape.get("type",0)) in [15,16]:result.append("approximate_box_surface_sampling")
  for key in ["randomDirectionAmount","sphericalDirectionAmount","randomPositionAmount"]:
   if float(shape.get(key,0))!=0:result.append("unsupported_shape:"+key)
  for key in ["radius","arc"]:
   if int(shape.get(key,{}).get("mode",0))!=0:result.append("unsupported_shape_distribution:"+key)
 if p.get("prewarm",false):result.append("unsupported_prewarm")
 if int(p.get("moveWithTransform",1))==2:result.append("unsupported_custom_simulation_space")
 var rate: Dictionary=p.get("EmissionModule",{}).get("rateOverTime",{})
 if int(rate.get("minMaxState",0)) in [1,2]:result.append("approximate_variable_emission_120hz")
 if absf(Curves.sample(p.get("EmissionModule",{}).get("rateOverDistance",{}),0,0))>0:result.append("unsupported_distance_emission")
 var velocity: Dictionary=p.get("VelocityModule",{})
 if velocity.get("enabled",false):
  for key in ["orbitalX","orbitalY","orbitalZ","orbitalOffsetX","orbitalOffsetY","orbitalOffsetZ","radial"]:
   if absf(Curves.sample(velocity.get(key,{}),0.5,0.5))>0:result.append("unsupported_velocity:"+key)
  if not is_equal_approx(Curves.sample(velocity.get("speedModifier",{}),0.5,0.5,1),1):result.append("unsupported_velocity:speedModifier")
  if velocity.get("inWorldSpace",false):result.append("unsupported_velocity_world_space")
 var uv: Dictionary=p.get("UVModule",{})
 if uv.get("enabled",false) and int(uv.get("mode",0))!=0:result.append("unsupported_sprite_uv_mode")
 if uv.get("enabled",false) and int(uv.get("timeMode",0))==1:result.append("unsupported_speed_uv_mode")
 return result

static func shader_custom_streams(renderer: Dictionary, custom0: Vector4, custom1: Vector4) -> Array[Vector4]:
 # Unity packs TEXCOORD channels consecutively, including across float4 boundaries.
 # Position/normal/tangent/color use separate semantics. UV occupies two channels;
 # UV2 supplies the other two only when listed. Custom1XYZW then starts wherever
 # the stream cursor is, not unconditionally at TEXCOORD1.
 # Apply only explicit source layouts; implicit/auto layouts remain unverified.
 if not renderer.get("m_UseCustomVertexStreams",false):return [custom0,custom1]
 var channels: Array[float]=[]
 for stream_value in renderer.get("m_VertexStreams",[]):
  var stream:int=int(stream_value)
  if stream in [0,1,2,3]:continue
  if stream in [4,5]:channels.append(0.0);channels.append(0.0)
  elif stream>=31 and stream<=34:
   for i in range(stream-30):channels.append(custom0[i])
  elif stream>=35 and stream<=38:
   for i in range(stream-34):channels.append(custom1[i])
  else:return [custom0,custom1] # Unknown extra semantics need their own source values.
 var tex1:=Vector4.ZERO;var tex2:=Vector4.ZERO
 for i in range(4):
  if channels.size()>i+4:tex1[i]=channels[i+4]
  if channels.size()>i+8:tex2[i]=channels[i+8]
 return [tex1,tex2]
