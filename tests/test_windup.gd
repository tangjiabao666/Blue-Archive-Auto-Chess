extends SceneTree
const Sim=preload("res://core/battle_sim.gd")
var fails=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize()->void:
	var s=Sim.new()
	var roster=[{"id":1,"team":0,"cell":Vector2i(0,3),"attack_windup_ticks":4},{"id":2,"team":1,"cell":Vector2i(0,2),"damage":0}]
	ck(s.configure(roster)=="","windup config accepted");s.start()
	var e=s.step()
	ck(s.units[1].hp==100,"windup doesn't apply immediate damage")
	var attack={}
	for event in e:
		if event.type=="attack" and event.actor_id==1:attack=event
	ck(attack.get("impact_tick",-1)==5,"event exposes authored contact tick")
	for i in range(3):s.step()
	ck(s.units[1].hp==100,"no early contact")
	s.step();ck(s.units[1].hp==90,"damage at contact tick")
	s.reset();s.start();s.step();s.reset();s.start()
	for i in range(5):s.step()
	ck(s.units[1].hp==90,"reset clears stale pending hits")
	s=Sim.new();roster[0].hp=10;roster[1].damage=10
	s.configure(roster);s.start();s.step()
	ck(s.phase=="finished" and s.units[1].hp==100,"dead actor doesn't complete attack windup")
	print("WINDUP FAILURES=",fails);quit(1 if fails else 0)
