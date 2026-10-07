extends SceneTree
const Rules=preload('res://core/lan/room_rules.gd')
var failures:=0
func ck(ok:bool,label:String):
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 var r=Rules.new();r.new_match(23,['p0','p1','p2'])
 for id in ['p0','p1','p2']:
  var p:Dictionary=r._player_ref(id);r._acquire_one_star(p,'yuuka');var unit:String=p.bench[0]
  ck(r.execute_for(id,{'type':'deploy_at','unit_id':unit,'point':Vector2(0,6.5)}).ok,'atomic deployment owner '+id)
  r._acquire_one_star(p,'yuuka');r._acquire_one_star(p,'yuuka');r._sync_positions(id)
  ck(p.units.size()==1 and p.units[0].star==2 and r.positions[id].size()==1,'merge has one valid owned placement')
 var v:Dictionary=r.player_view('p1');v.player.gold=999;v.positions.clear()
 ck(r.get_player('p1').gold==10 and not r.positions.p1.is_empty(),'UI snapshots detached from authority')
 r._state.round=3;r._prepare_round()
 for id in ['p0','p1','p2']:
  ck(r.get_player(id).reinforcement.status=='pending' and not r.set_ready(id,true).ok,'each human must resolve own round3 reinforcement')
  ck(r.execute_for(id,{'type':'skip_reinforcement','round':3}).ok and r.set_ready(id,true).ok,'skip then ready succeeds for owner')
 var before:Dictionary=r.snapshot();ck(not r.execute_for('p3',{'type':'refresh_shop'}).ok and r.snapshot()==before,'network clients cannot issue AI-seat economy commands')
 print('LAN_PREPARATION_EDGES failures=',failures);quit(1 if failures else 0)
