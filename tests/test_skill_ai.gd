extends SceneTree
const Sim=preload("res://core/battle_sim.gd")
var fails=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func u(id:int,team:int,cell:Vector2i,extra:Dictionary={})->Dictionary:
	var d={"id":id,"team":team,"cell":cell,"hp":1000,"damage":0,"range":10};d.merge(extra,true);return d
func _initialize()->void:
	var s=Sim.new()
	s.configure([u(1,0,Vector2i(0,3),{"skill_cooldown_ticks":30,"skill_recovery_ticks":5}),u(2,1,Vector2i(0,2))]);s.start()
	var casts=[]
	for i in range(150):
		for e in s.step():
			if e.type=="skill" and e.actor_id==1:casts.append(e.tick)
	ck(casts.size()>=3,"EX triggers from cooldown, not four-attack energy")
	if not casts.is_empty():ck(casts[0]>=30,"initial EX cooldown respected")
	for i in range(1,casts.size()):ck(casts[i]-casts[i-1]>=30,"independent EX cooldown respected")
	# Area aims at two adjacent enemies, not isolated nearest one.
	s=Sim.new();s.configure([u(1,0,Vector2i(0,3),{"skill":"area","skill_cooldown_ticks":1}),u(2,1,Vector2i(0,2)),u(3,1,Vector2i(4,0)),u(4,1,Vector2i(5,0))]);s.start()
	var chosen=-1
	for e in s.step():
		if e.type=="skill" and e.actor_id==1:chosen=e.target_id
	ck(chosen==3,"AOE chooses clustered targets")
	# Shield is held if safe even though cooldown is ready.
	s=Sim.new();s.configure([u(1,0,Vector2i(0,3),{"skill":"shield","skill_cooldown_ticks":1}),u(2,1,Vector2i(0,2))]);s.start()
	var shield_cast=false
	for i in range(50):
		for e in s.step():
			if e.type=="skill" and e.actor_id==1:shield_cast=true
	ck(not shield_cast,"AI holds shield against zero-damage enemies")
	# A threatened low-health unit casts shielding, no manual command needed.
	s=Sim.new();s.configure([u(1,0,Vector2i(0,3),{"hp":100,"skill":"shield","skill_cooldown_ticks":1,"attack_ticks":1}),u(2,1,Vector2i(0,2),{"damage":10,"attack_ticks":1,"skill_cooldown_ticks":1000})]);s.start()
	shield_cast=false
	for i in range(8):
		for e in s.step():
			if e.type=="skill" and e.actor_id==1:shield_cast=true
	ck(shield_cast,"AI shields under real pressure")
	print("SKILL AI FAILURES=",fails);quit(1 if fails else 0)
