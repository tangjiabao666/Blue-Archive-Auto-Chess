extends RefCounted
## Pure sampling helpers for exported Unity MinMaxCurve/MinMaxGradient.
## Unity particle curve states differ from gradient states. No engine TIME/RNG.
static func sample(c: Dictionary, t: float, r: float = 0.0, fallback: float = 0.0) -> float:
 if c.is_empty(): return fallback
 var mode: int = int(c.get("minMaxState", 0))
 var multiplier: float = float(c.get("scalar", 1.0))
 if mode == 0: return multiplier
 if mode == 3: return lerpf(float(c.get("minScalar", multiplier)), multiplier, r)
 var high: float = curve(c.get("maxCurve", {}), t)
 if mode == 2: return lerpf(curve(c.get("minCurve", {}), t), high, r) * multiplier
 return high * multiplier

static func curve(c: Dictionary, t: float) -> float:
 var keys: Array = c.get("m_Curve", [])
 if keys.is_empty(): return 0.0
 if t <= float(keys[0].time): return float(keys[0].value)
 if t >= float(keys[-1].time): return float(keys[-1].value)
 for i in range(1, keys.size()):
  var a: Dictionary = keys[i-1]; var b: Dictionary = keys[i]
  if t > float(b.time): continue
  var span: float = float(b.time) - float(a.time)
  if span <= 0.0: return float(b.value)
  var out_s: float = float(a.get("outSlope", 0.0)); var in_s: float = float(b.get("inSlope", 0.0))
  if absf(out_s) >= 1e20 or absf(in_s) >= 1e20: return float(a.value)
  var u: float = (t - float(a.time)) / span
  var weighted: bool = int(a.get("weightedMode", 0)) & 2 or int(b.get("weightedMode", 0)) & 1
  if weighted:
   var wa: float = float(a.get("outWeight", 1.0/3.0)) if int(a.get("weightedMode", 0)) & 2 else 1.0/3.0
   var wb: float = float(b.get("inWeight", 1.0/3.0)) if int(b.get("weightedMode", 0)) & 1 else 1.0/3.0
   var lo: float = 0.0; var hi: float = 1.0
   for k in range(28):
    var mid: float = (lo+hi)*0.5
    if bezier(0.0,wa,1.0-wb,1.0,mid) < u: lo = mid
    else: hi = mid
   return bezier(float(a.value),float(a.value)+out_s*span*wa,float(b.value)-in_s*span*wb,float(b.value),(lo+hi)*0.5)
  return (2*u*u*u-3*u*u+1)*float(a.value)+(u*u*u-2*u*u+u)*span*out_s+(-2*u*u*u+3*u*u)*float(b.value)+(u*u*u-u*u)*span*in_s
 return float(keys[-1].value)

static func bezier(a: float,b: float,c: float,d: float,t: float) -> float:
 var u: float = 1.0-t
 return u*u*u*a+3*u*u*t*b+3*u*t*t*c+t*t*t*d

static func integral(c: Dictionary, t: float, r: float = 0.0) -> float:
 if t <= 0.0: return 0.0
 var mode: int=int(c.get("minMaxState",0))
 if mode in [0,3]: return sample(c,0.0,r)*t
 var high: float=curve_integral(c.get("maxCurve",{}),t)
 if mode==2:return lerpf(curve_integral(c.get("minCurve",{}),t),high,r)*float(c.get("scalar",1))
 return high*float(c.get("scalar",1))

static func curve_integral(c: Dictionary,t: float)->float:
 var keys: Array=c.get("m_Curve",[])
 if keys.is_empty() or t<=0:return 0.0
 if keys.size()==1:return t*float(keys[0].value)
 var result: float=maxf(0,minf(t,float(keys[0].time)))*float(keys[0].value)
 for i in range(1,keys.size()):
  var a: Dictionary=keys[i-1];var b: Dictionary=keys[i]
  var lo: float=maxf(0,float(a.time));var hi: float=minf(t,float(b.time))
  if hi<=lo:continue
  var span: float=float(b.time)-float(a.time)
  var out_s: float=float(a.get("outSlope",0));var in_s: float=float(b.get("inSlope",0))
  if absf(out_s)>=1e20 or absf(in_s)>=1e20:result+=(hi-lo)*float(a.value);continue
  var weighted: bool=int(a.get("weightedMode",0))&2 or int(b.get("weightedMode",0))&1
  if weighted:
   var step: float=(hi-lo)/16.0
   for j in range(16):
    var center: float=lo+(float(j)+0.5)*step;var offset: float=step*0.2886751345948129
    result+=(curve(c,center-offset)+curve(c,center+offset))*step*0.5
  else:
   var u: float=(lo-float(a.time))/span;var v: float=(hi-float(a.time))/span
   var powers: Vector4=Vector4(v-u,v*v-u*u,v*v*v-u*u*u,v*v*v*v-u*u*u*u)
   result+=span*(float(a.value)*(0.5*powers.w-powers.z+powers.x)+out_s*span*(0.25*powers.w-2.0/3.0*powers.z+0.5*powers.y)+float(b.value)*(-0.5*powers.w+powers.z)+in_s*span*(0.25*powers.w-1.0/3.0*powers.z))
 if t>float(keys[-1].time):result+=(t-maxf(0,float(keys[-1].time)))*float(keys[-1].value)
 return result

static func color_value(c: Dictionary, fallback: Color = Color.WHITE) -> Color:
 return Color(float(c.get("r",fallback.r)),float(c.get("g",fallback.g)),float(c.get("b",fallback.b)),float(c.get("a",fallback.a)))

# Compile immutable key decoding, retaining a copy to validate hash collisions
# and caller mutation. Bounded process-local cache; no source data is rewritten.
static var _gradient_cache:Dictionary={}
static var _gradient_compilations:int=0
static var _gradient_hits:int=0
static func clear_gradient_cache()->void:
 _gradient_cache.clear();_gradient_compilations=0;_gradient_hits=0

static func gradient_cache_stats()->Dictionary:
 return {"entries":_gradient_cache.size(),"compilations":_gradient_compilations,"hits":_gradient_hits}

static func _gradient_recipe(g:Dictionary)->Dictionary:
 var key:int=g.hash()
 var cached:Dictionary=_gradient_cache.get(key,{})
 if not cached.is_empty() and cached.source==g:
  _gradient_hits+=1
  return cached
 var tracks:Array=[]
 for alpha in [false,true]:
  var count:int=int(g.get("m_NumAlphaKeys" if alpha else "m_NumColorKeys",0))
  var prefix:String="atime" if alpha else "ctime"
  var colors:Array[Color]=[];var starts:Array[float]=[];var ends:Array[float]=[]
  for i in range(maxi(0,count)):
   colors.append(color_value(g.get("key%d"%i,{})))
   starts.append(float(g.get(prefix+str(i),0))/65535.0)
   ends.append(float(g.get(prefix+str(i),65535))/65535.0)
  tracks.append({"colors":colors,"starts":starts,"ends":ends})
 cached={"source":g.duplicate(true),"initial":color_value(g.get("key0",{})),"fixed":int(g.get("m_Mode",0))==1,"tracks":tracks}
 if _gradient_cache.size()>=256:_gradient_cache.clear()
 _gradient_cache[key]=cached;_gradient_compilations+=1
 return cached

static func gradient(g: Dictionary, t: float) -> Color:
 if g.is_empty():return Color.WHITE
 var recipe:Dictionary=_gradient_recipe(g)
 var result:Color=recipe.initial
 for track_index in range(2):
  var track:Dictionary=recipe.tracks[track_index]
  var count:int=track.colors.size()
  if count<=0:continue
  var value:Color=track.colors[count-1]
  if t<=track.starts[0]:value=track.colors[0]
  else:
   for i in range(1,count):
    var end:float=track.ends[i]
    if t>end:continue
    var start:float=track.starts[i-1]
    var a:Color=track.colors[i-1];var b:Color=track.colors[i]
    value=(b if t>=end else a) if recipe.fixed else a.lerp(b,clampf((t-start)/maxf(end-start,0.000001),0,1))
    break
  if track_index==1:result.a=value.a
  else:result.r=value.r;result.g=value.g;result.b=value.b
 return result

static func minmax_color(c: Dictionary, t: float, r: float = 0.0) -> Color:
 if c.is_empty(): return Color.WHITE
 match int(c.get("minMaxState",0)):
  0: return color_value(c.get("maxColor",{}))
  1: return gradient(c.get("maxGradient",{}),t)
  2: return color_value(c.get("minColor",{})).lerp(color_value(c.get("maxColor",{})),r)
  3: return gradient(c.get("minGradient",{}),t).lerp(gradient(c.get("maxGradient",{}),t),r)
  4: return gradient(c.get("maxGradient",{}),r)
 return Color.WHITE

static func unity_vector(v: Dictionary) -> Vector3:
 return Vector3(float(v.get("x",0)),float(v.get("y",0)),-float(v.get("z",0)))

static func unity_transform(t: Dictionary) -> Transform3D:
 var q: Dictionary = t.get("m_LocalRotation",{})
 var quaternion := Quaternion(-float(q.get("x",0)),-float(q.get("y",0)),float(q.get("z",0)),float(q.get("w",1))).normalized()
 var scale: Dictionary = t.get("m_LocalScale",{})
 return Transform3D(Basis(quaternion).scaled_local(Vector3(float(scale.get("x",1)),float(scale.get("y",1)),float(scale.get("z",1)))),unity_vector(t.get("m_LocalPosition",{})))

static func sheet(module: Dictionary,t: float,age: float,r: float) -> Vector4:
 if not module.get("enabled",false): return Vector4(1,1,0,0)
 var nx: int = maxi(1,int(module.get("tilesX",1))); var ny: int = maxi(1,int(module.get("tilesY",1)))
 var frames: int = nx if int(module.get("animationType",0)) == 1 else nx*ny
 var normalized: float = sample(module.get("frameOverTime",{}),t,r)*float(module.get("cycles",1))
 var f: int = int(floor((sample(module.get("startFrame",{}),0,r)+normalized)*float(frames)))
 if int(module.get("timeMode",0)) == 2: f = int(floor(age*float(module.get("fps",30))))
 f = posmod(f,frames)
 var row: int = int(f/nx)
 if int(module.get("animationType",0)) == 1: row = int(module.get("rowIndex",0)) if int(module.get("rowMode",1)) == 1 else mini(ny-1,int(r*ny))
 return Vector4(1.0/nx,1.0/ny,float(f%nx)/nx,1.0-float(row+1)/ny)
