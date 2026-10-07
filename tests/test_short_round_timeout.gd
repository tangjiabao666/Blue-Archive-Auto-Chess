extends SceneTree
const Sim=preload('res://core/tactical_sim.gd')
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 var sim=Sim.new()
 var roster:Array=[{'id':0,'team':0,'character_id':'yuuka','star':1,'cell':Vector2(0,4)},{'id':7,'team':1,'character_id':'serika','star':1,'cell':Vector2(0,-4)}]
 ck(sim.configure(roster,{'max_ticks':2,'timeout_total_hp':true}).is_empty(),'explicit total-HP timeout policy configures')
 if failures:quit(1);return
 sim.start();sim.units[0].hp=800;sim.units[0].max_hp=40000;sim.units[1].hp=600;sim.units[1].max_hp=1000;sim.units[1].shield=90000
 sim.tick=1;sim._check_finish();ck(sim.phase=='running','no early timeout')
 sim.tick=2;sim._check_finish();ck(sim.winner==0 and sim.phase=='finished','higher absolute HP wins even with lower ratio and smaller shield')
 ck(sim.units[1].hp==600,'loser survivors keep their real HP')
 sim.reset();sim.start();sim.units[0].hp=500;sim.units[1].hp=500;sim.units[1].shield=90000;sim.tick=2;sim._check_finish();ck(sim.winner==-1,'equal HP is draw regardless of shield')
 sim.configure(roster,{'max_ticks':2});sim.start();sim.units[0].hp=800;sim.units[1].hp=600;sim.tick=2;sim._check_finish();ck(sim.winner==-1,'historical timeout still draws')
 var old:Dictionary=sim.snapshot()
 ck(not sim.configure(roster,{'timeout_total_hp':'yes'}).is_empty() and sim.snapshot()==old,'invalid timeout policy rejects atomically')
 print('SHORT_ROUND_TIMEOUT checks=',checks,' failures=',failures);quit(1 if failures else 0)
