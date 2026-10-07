extends SceneTree
const Particles=preload("res://vfx/native_particles.gd")
const Curves=preload("res://vfx/native_curves.gd")
const Source=preload("res://vfx/native_source.gd")
const ROOT="res://data/effects"
var failures:=0
var checks:=0
var report:Array=[]
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:
 var sources:Array=["shiroko","hoshino","hina","aru","yuuka","aris","serika","shared-weapons"]
 var streams:=0
 for character in sources:
  var data:Dictionary=Source.read_json(ROOT+"/"+character+"/visual-templates.json")
  for prefab in data.get("prefabs",[]):
   for node in prefab.get("nodes",[]):
    for component in node.get("components",[]):
     if component.get("type")!="ParticleSystem":continue
     var p:Dictionary=component.nativeParameters
     var custom:Dictionary=p.get("CustomDataModule",{})
     if not custom.get("enabled",false) or int(custom.get("mode1",0))!=2:continue
     var particles:Array=Particles.emit(p,7193,20.0,256)
     if particles.is_empty():continue
     streams+=1
     var particle:Dictionary=particles[0]
     for normalized in [0.0,0.25,0.75]:
      var state:Dictionary=Particles.state(p,particle,float(particle.birth)+float(particle.life)*normalized)
      var expected:Color=Curves.minmax_color(custom.color1,normalized,particle.fractions[21])
      var expected_vector:=Vector4(expected.r,expected.g,expected.b,expected.a)
      ck((state.custom1 as Vector4).is_equal_approx(expected_vector),"source custom color missing: "+character+"/"+prefab.name+"/"+node.name+" @"+str(normalized))
      if character=="aris" and prefab.name=="FX_Aris_Original_Ex01_Motion_Shot" and node.name=="smoke" and normalized==0.25:
       ck(state.custom1.z>31.9,"HDR purple color is not clamped to LDR")
       report.append({"source":component.source,"normalized_age":normalized,"expected_custom1":[expected.r,expected.g,expected.b,expected.a],"actual_custom1":[state.custom1.x,state.custom1.y,state.custom1.z,state.custom1.w],"particle_color":[state.color.r,state.color.g,state.color.b,state.color.a],"custom0":[state.custom0.x,state.custom0.y,state.custom0.z,state.custom0.w]})
 # Cover both native custom slots, disabled behavior and unchanged vector semantics.
 var synthetic:Dictionary={"InitialModule":{"startLifetime":{"scalar":1.0},"startSize":{"scalar":1.0}},"EmissionModule":{"enabled":true,"m_Bursts":[{"time":0.0,"countCurve":{"scalar":1.0}}]},"CustomDataModule":{"enabled":true,"mode0":2,"color0":{"minMaxState":0,"maxColor":{"r":4.0,"g":2.0,"b":1.0,"a":0.3}},"mode1":1,"vector1_0":{"scalar":7.0}}}
 var particle:Dictionary=Particles.emit(synthetic,1,1.0)[0]
 var state:Dictionary=Particles.state(synthetic,particle,0.2)
 ck((state.custom0 as Vector4).is_equal_approx(Vector4(4,2,1,0.3)),"Custom1 native Color mode maps RGBA to first float4")
 ck(state.custom1==Vector4(7,0,0,0),"vector mode unchanged")
 synthetic.CustomDataModule.enabled=false
 state=Particles.state(synthetic,particle,0.2)
 ck(state.custom0==Vector4.ZERO and state.custom1==Vector4.ZERO,"disabled custom data still zero")
 print("SMOKE_CUSTOM_COLOR ",checks," checks; ",failures," failures; ",streams," original emitters")
 quit(1 if failures else 0)
