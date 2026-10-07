extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 ck(ResourceLoader.exists('res://core/lan/authority.gd'),'room authority exists')
 if failures:quit(1);return
 var a=load('res://core/lan/authority.gd').new();ck(a.start_match(23).ok,'authority creates match')
 a.rules._pairs=[['p0','p3'],['p1','p4'],['p2','p5'],['p6','p7']] # Deliberate pairing fixture, not random-match evidence.
 for id in ['p0','p1','p2']:
  var bought:Dictionary=a.submit_intent(id,{'round':1,'controller_epoch':0,'sequence':0,'command':{'type':'buy_offer','slot':0}})
  ck(bought.ok,'each participant buys through authority')
  a.submit_intent(id,{'round':1,'controller_epoch':0,'sequence':1,'command':{'type':'deploy_unit','unit_id':bought.unit_id}})
  a.submit_intent(id,{'round':1,'controller_epoch':0,'sequence':2,'command':{'type':'ready','value':true}})
 ck(a.rules.snapshot().phase=='loading' and a.duels.size()==3 and a.ai_jobs.size()==1,'three distinct human arenas plus one AI pair')
 var before:Dictionary=a.rules.get_player('p1');ck(a.submit_intent('p1',{'round':1,'controller_epoch':0,'sequence':2,'command':{'type':'ready','value':true}}).ok and a.rules.get_player('p1')==before,'duplicate request cannot reapply')
 a.mark_loaded('p0');a.mark_loaded('p1');ck(a.rules.snapshot().phase=='loading','third loader is a real barrier')
 a.mark_loaded('p2');ck(a.rules.snapshot().phase=='battle','all three load then start together')
 a.advance(0.1)
 for duel in a.duels.values():ck(duel.clock.sim.tick==2,'all real arenas advance same simulation time')
 var view:Dictionary=a.view_for('p1');ck(view.battle.left_id=='p1' and not view.has('players'),'local seat receives own match only')
 a.close();print('LAN_MULTI_DUEL checks=',checks,' failures=',failures);quit(1 if failures else 0)
