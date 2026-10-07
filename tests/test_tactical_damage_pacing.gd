extends SceneTree
const Sim=preload('res://core/tactical_sim.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func make(scale:float):
 var sim=Sim.new()
 var error:String=sim.configure([{'id':0,'team':0,'character_id':'serika','star':1,'cell':Vector2(0,2)},{'id':1,'team':1,'character_id':'yuuka','star':1,'cell':Vector2(0,-2)}],{'random_damage':false,'tactical_damage_scale':scale,'overtime_enabled':true,'overtime_start_seconds':75.0,'overtime_ramp_seconds':30.0})
 ck(error.is_empty(),'explicit league damage factor accepted')
 return sim if error.is_empty() else null
func _initialize()->void:
 var tuned=make(0.18)
 if tuned==null:finish();return
 var base=make(1.0)
 for at in [0,1000,1500,1800,2100,3000]:
  tuned.tick=at;base.tick=at
  var raw:float=base.damage_components(base.units[0],base.units[1],1.7).raw
  var value:float=tuned.damage_components(tuned.units[0],tuned.units[1],1.7).raw
  var expected:float=0.18+0.82*clampf((at-1500.0)/600.0,0.0,1.0)
  ck(is_equal_approx(value,raw*expected),'damage scales once with declared overtime ramp '+str(at))
 ck(tuned.character_data('serika')==base.character_data('serika'),'source skill and character numbers unchanged')
 ck(tuned.units[0].max_hp==base.units[0].max_hp,'damage pacing does not secretly inflate displayed HP')
 for value in [0.0,-1.0,1.1,NAN,INF,true,'0.18']:
  var before:Dictionary=tuned.snapshot()
  ck(not tuned.configure([],{'tactical_damage_scale':value}).is_empty() and tuned.snapshot()==before,'invalid pacing rejects atomically '+str(value))
 finish()
func finish()->void:print('TACTICAL_DAMAGE_PACING checks=',checks,' failures=',failures);quit(1 if failures else 0)
