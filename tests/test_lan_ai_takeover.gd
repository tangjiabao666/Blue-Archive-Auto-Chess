extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 var a=load('res://core/lan/authority.gd').new();a.start_match(23)
 if not a.has_method('take_over'):ck(false,'takeover available');quit(1);return
 a.rules._pairs=[['p0','p1'],['p2','p3'],['p4','p5'],['p6','p7']]
 for id in ['p0','p1','p2']:
  var b=a.rules.execute_for(id,{'type':'buy_offer','slot':0})
  a.rules.execute_for(id,{'type':'deploy_unit','unit_id':b.unit_id});a.rules.set_ready(id,true)
 a.begin_round()
 for id in ['p0','p1','p2']:a.mark_loaded(id)
 var d=a.duels[a._participant_duel.p1];var sim=d.clock.sim
 d.queue_intent(0,{'type':'move','actor_id':0,'point':Vector2(0,3)})
 d.queue_intent(1,{'type':'move','actor_id':7,'point':Vector2(0,-3)})
 var units=sim.units.duplicate(true);var resources=sim._resources.snapshot();var rng=sim._rng.state
 ck(a.take_over('p1').ok,'nonhost takeover accepted')
 ck(sim.units==units and sim._resources.snapshot()==resources and sim._rng.state==rng and sim.tick==0,'takeover preserves entire live state before tick')
 ck(sim._commands.snapshot().pending.size()==1 and sim._commands.snapshot().pending[0].team==0,'only dropped team pending inputs cancelled')
 ck(a.rules.controllers.p1=='ai' and a.controller_epochs.p1==1,'controller epoch revoked')
 ck(not a.submit_intent('p1',{'round':1,'controller_epoch':0,'sequence':9,'command':{'type':'ready','value':true}}).ok,'stale human cannot act')
 ck(not a.take_over('p0').ok,'host cannot migrate')
 a.advance(0.5)
 ck(1 in sim._ai.snapshot().teams and sim.tick==10,'AI joins ordinary cadence without reset')
 ck(d.next_sequence(1)>=1,'human and AI share sequence allocator')
 ck(a.take_over('p1').ok and a.controller_epochs.p1==1,'idempotent drop')
 a.close();a.start_match(24)
 ck(a.take_over('p1').ok and a.rules.ready.p1 and not a.rules.get_player('p1').deployed.is_empty(),'preparation takeover buys and fields AI once')
 var p=a.rules.get_player('p1');a.take_over('p1');ck(a.rules.get_player('p1')==p,'no duplicate AI purchases')
 a.close();a.start_match(25)
 var b=a.rules.execute_for('p1',{'type':'buy_offer','slot':0});a.rules.execute_for('p1',{'type':'deploy_unit','unit_id':b.unit_id});a.rules.set_ready('p1',true)
 var locked=a.rules.get_player('p1');a.take_over('p1');ck(a.rules.get_player('p1')==locked,'ready player army and economy stay locked after drop')
 a.close();print('LAN_AI_TAKEOVER checks=',checks,' failures=',failures);quit(1 if failures else 0)
