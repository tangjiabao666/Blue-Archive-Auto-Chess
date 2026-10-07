extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func setup_match():
 var a=load('res://core/lan/authority.gd').new();a.start_match(41)
 for id in ['p0','p1','p2']:
  var b=a.rules.execute_for(id,{'type':'buy_offer','slot':0});a.rules.execute_for(id,{'type':'deploy_unit','unit_id':b.unit_id});a.rules.set_ready(id,true)
 a.begin_round();return a
func _initialize():
 var a=setup_match();a.mark_loaded('p0');a.mark_loaded('p1');a.advance(8)
 ck(a.rules._state.phase=='loading' and a.duels.values().all(func(d):return d.clock.sim.tick==0),'late loader keeps every clock frozen')
 a.take_over('p2');ck(a.rules._state.phase=='battle','loading dropout removed from barrier')
 a.take_over('p1');ck(a.rules.controllers.p1=='ai' and a.rules.controllers.p2=='ai','both clients can drop')
 a.close();a=setup_match()
 for id in ['p0','p1','p2']:a.mark_loaded(id)
 for d in a.duels.values():
  d.clock.sim.tick=1799
  for u in d.clock.sim.units:u.normal_ready=999999;u.basic_ready=999999
 a.advance(0.05)
 for i in range(100):
  if a.rules._state.phase=='result':break
  a.advance(0.05)
 ck(a.rules._state.phase=='result','all results finish')
 a.request_next('p0');a.request_next('p1');ck(a.rules._state.round==1,'next round waits for third human')
 a.take_over('p2');ck(a.rules._state.round==2 and a.rules._state.phase=='preparation','result dropout releases next-round barrier')
 a.close();print('LAN_LIFECYCLE checks=',checks,' failures=',failures);quit(1 if failures else 0)
