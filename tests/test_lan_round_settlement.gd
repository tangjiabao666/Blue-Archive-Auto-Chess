extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 ck(ResourceLoader.exists('res://core/lan/authority.gd'),'room authority exists')
 if failures:quit(1);return
 var a=load('res://core/lan/authority.gd').new();a.start_match(7)
 for round_index in range(1,7):
  for id in ['p0','p1','p2']:
   if a.rules.get_player(id).deployed.is_empty():
    var bought:Dictionary=a.rules.execute_for(id,{'type':'buy_offer','slot':0});a.rules.execute_for(id,{'type':'deploy_unit','unit_id':bought.unit_id})
   if a.rules.get_player(id).reinforcement.get('status')=='pending':a.rules.execute_for(id,{'type':'skip_reinforcement','round':round_index})
   a.rules.set_ready(id,true)
  ck(a.begin_round().ok,'freeze round '+str(round_index))
  for id in ['p0','p1','p2']:a.mark_loaded(id)
  for job in a.ai_jobs:
   job.advance(1);job._simulation.tick=1799
   for u in job._simulation.units:u.attack_ready=99999;u.basic_ready=99999;u.sub_ready=99999;u.skill_ready=99999
   job.run()
  for duel in a.duels.values():
   duel.clock.sim.tick=1799
   for u in duel.clock.sim.units:u.attack_ready=99999;u.basic_ready=99999;u.sub_ready=99999;u.skill_ready=99999
  ck(a.rules.league.snapshot().rounds.size()==round_index-1,'no partial round score')
  a.advance(0.05)
  ck(a.rules.snapshot().phase==('finished' if round_index==6 else 'result'),'four results settle once')
  ck(a.rules.league.snapshot().rounds.size()==round_index,'one ledger record for complete round')
  var saved:Dictionary=a.rules.snapshot();a.advance(1.0);ck(a.rules.snapshot()==saved,'repeat tick cannot award twice')
  if round_index<6:ck(a.next_round().ok,'advance after result')
 a.close();print('LAN_ROUND_SETTLEMENT checks=',checks,' failures=',failures);quit(1 if failures else 0)
