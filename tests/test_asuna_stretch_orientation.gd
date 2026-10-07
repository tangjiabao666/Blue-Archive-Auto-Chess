extends SceneTree
const Stretch=preload("res://vfx/native_stretch_orientation.gd")
const Particles=preload("res://vfx/native_particles.gd")
const Curves=preload("res://vfx/native_curves.gd")
var failed:=0
var checks:=0
var source_blocked:=false
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failed+=1;printerr("FAIL: "+label)
func camera(at:float)->Dictionary:
 var t:=Transform3D(Basis.IDENTITY,Vector3(0,0,10))
 return {"transform":t,"projection":"orthographic","time":at}
func _initialize():
 var legacy:=Transform3D(Basis.IDENTITY.scaled(Vector3(0.05,2,0.05)),Vector3(3,4,5))
 var r:Dictionary=Stretch.orient(legacy,Vector3(30,0,0),camera(0.1),0.1)
 check(r.applied,"synthetic horizontal particle accepted")
 check(r.transform.basis.y.normalized().dot(Vector3.RIGHT)>0.99999,"long axis follows horizontal velocity rather than camera-up")
 check(r.transform.origin==legacy.origin,"orientation leaves center unchanged")
 check(r.transform.basis.get_scale().is_equal_approx(legacy.basis.get_scale()),"orientation leaves legacy dimensions unchanged")
 for velocity in [Vector3(0,30,0),Vector3(4,-2,8),Vector3(0,0,20),Vector3(0,0,-20),Vector3(1e-9,0,20)]:
  var a:Dictionary=Stretch.orient(legacy,velocity,camera(0.1),0.1)
  check(a.applied and a.transform.is_finite(),"finite basis including head-on limit")
  check(a.transform.basis.y.normalized().dot(velocity.normalized())>0.99999,"velocity-aligned Y in all directions")
  check(absf(a.transform.basis.orthonormalized().determinant()-1)<0.00001,"proper handedness")
  check(a.transform==Stretch.orient(legacy,velocity,camera(0.1),0.1).transform,"repeat is bitwise deterministic")
 for bad in [{},camera(0.2),{"transform":Transform3D.IDENTITY,"projection":"unknown","time":0.1}]:
  var a:Dictionary=Stretch.orient(legacy,Vector3.RIGHT,bad,0.1)
  check(not a.applied and a.transform==legacy,"invalid camera leaves legacy transform unchanged")
 var stationary:Dictionary=Stretch.orient(legacy,Vector3.ZERO,camera(0.1),0.1)
 check(not stationary.applied and stationary.transform==legacy,"zero velocity fallback is explicit and finite")
 var perspective:Dictionary=camera(0.1);perspective.projection="perspective"
 var facing:Dictionary=Stretch.orient(legacy,Vector3.RIGHT,perspective,0.1)
 check(facing.applied and facing.transform.basis.z.dot(perspective.transform.origin-legacy.origin)>0,"perspective normal points toward camera")
 var earlier:Dictionary=Stretch.orient(legacy,Vector3.RIGHT,camera(0.05),0.05)
 var later:Dictionary=Stretch.orient(legacy,Vector3.RIGHT,camera(0.9),0.9)
 check(earlier.transform==later.transform,"absolute-time snapshots are independent of call order")
 if not "--synthetic-only" in OS.get_cmdline_user_args():actual_source_cases()
 print("STRETCH_TEST checks=%d failures=%d source_blocked=%s"%[checks,failed,str(source_blocked)])
 quit(1 if failed else 2 if source_blocked else 0)
func actual_source_cases()->void:
 if not FileAccess.file_exists("res://data/effects/asuna/asuna/visual-templates.json"):
  source_blocked=true;printerr("BLOCKED: recovered exact basic source not supplied");return
 var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/effects/asuna/asuna/visual-templates.json"))
 var source_path:String="FX_Public_AR_Motion_Shot_Asuna/Muzzle_Line"
 var prefab:Dictionary={};var node:Dictionary={}
 for f in data.prefabs:
  if f.name=="FX_Public_AR_Motion_Shot_Asuna":prefab=f
 for n in prefab.get("nodes",[]):
  if n.hierarchy==source_path:node=n
 if node.is_empty():source_blocked=true;printerr("BLOCKED: exact Muzzle_Line node absent");return
 var p:Dictionary={};var render:Dictionary={};var source:Dictionary={}
 for c in node.components:
  if c.type=="ParticleSystem":p=c.nativeParameters;source=c.source
  if c.type=="ParticleSystemRenderer":render=c.nativeParameters
 var seed:int=9751 ^ (str(source.cab)+"/"+str(source.pathId)).hash()
 var particles:Array=Particles.emit(p,seed,2.4333333333333336)
 var at:float=431.0/60.0
 var cam:Dictionary=camera(at)
 cam.transform=Transform3D(Basis.looking_at(Vector3(5,-4,-7)),Vector3(-5,4.55,7))
 var rows:Array=[]
 # Historical cast starts retained from prior verified replay. They are not
 # revalidated here because the restored main core lacks the Asuna mechanic.
 for start in [5.2,5.7]:
  var local_time:float=at-start-0.5333333333333333
  for i in particles.size():
   var sample:Dictionary=particles[i]
   var state:Dictionary=Particles.state(p,sample,local_time)
   if not state.visible:continue
   var dims:Vector3=state.size;dims.y*=float(render.m_LengthScale)
   var legacy:=Transform3D(Basis.IDENTITY.scaled(dims),state.position)
   var velocity:Vector3=sample.direction*float(sample.start_speed)*float(sample.simulation_speed)
   var a:Dictionary=Stretch.orient(legacy,velocity,cam,at)
   check(a.applied,"actual source particle accepted")
   check(a.transform.basis.y.normalized().dot(velocity.normalized())>0.99999,"actual source long axis follows represented velocity")
   check(a.transform.basis.get_scale().is_equal_approx(legacy.basis.get_scale()),"actual source dimensions unchanged")
   var epsilon:float=0.00001
   var next:Dictionary=Particles.state(p,sample,local_time+epsilon)
   if next.visible:
    var derivative:Vector3=(next.position-state.position)/epsilon
    check(derivative.normalized().dot(velocity.normalized())>0.999,"actual analytic velocity follows current particle trajectory")
   rows.append({"cast_start":start,"local_time":local_time,"particle_index":i,"birth":sample.birth,"age":state.age,"life":sample.life,"position":str(state.position),"velocity":str(velocity),"legacy_dimensions":str(dims),"candidate_long_axis":str(a.transform.basis.y.normalized()),"legacy_camera_up_alignment_to_velocity":absf(cam.transform.basis.y.normalized().dot(velocity.normalized()))})
 check(rows.size()>0,"frame 0430 source sample times have live muzzle-line particles")
 FileAccess.open("res://evidence/asuna-stretch/source-particle-cases.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
 print("SOURCE_CASES=",rows.size()," ",JSON.stringify(rows))
