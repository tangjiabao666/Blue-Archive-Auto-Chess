extends SceneTree
const Sim = preload("res://core/battle_sim.gd")
var failed := 0
func ck(value:bool,label:String)->void:
	if not value: failed += 1; printerr("FAIL: "+label)
func u(id:int,team:int,cell:Vector2i,extra:Dictionary={}) -> Dictionary:
	var d={"id":id,"team":team,"cell":cell};d.merge(extra,true);return d
func _initialize()->void:
	var s=Sim.new()
	s.configure([u(1,0,Vector2i(0,4)),u(2,1,Vector2i(0,1))]);s.start()
	var ev=s.step();var moved=[];var attacked=[]
	for e in ev:
		if e.type=="move":moved.append(e.actor_id)
		if e.type=="attack":attacked.append(e.actor_id)
	for id in moved:ck(not attacked.has(id),"moving unit waits for arrival before shooting")
	# Four attacks generate energy; skill cannot interrupt previous attack cooldown.
	s=Sim.new();s.configure([u(1,0,Vector2i(0,3),{"hp":1000}),u(2,1,Vector2i(0,2),{"hp":1000})]);s.start()
	var last_attack=-100;var skill_tick=-1
	for i in range(200):
		for e in s.step():
			if e.actor_id==1 if e.has("actor_id") else false:
				if e.type=="attack":last_attack=e.tick
				if e.type=="skill":skill_tick=e.tick;ck(skill_tick-last_attack>=20,"skill respects preceding attack recovery")
	ck(skill_tick>0,"skill still occurs")
	# Shield applied on cast tick absorbs incoming damage and expires after 80 ticks.
	s=Sim.new();s.configure([u(1,0,Vector2i(0,3),{"hp":1000,"skill":"shield","skill_power":20}),u(2,1,Vector2i(0,2),{"hp":1000})]);s.start()
	var absorbed=0
	for i in range(600):
		for e in s.step():
			if e.type=="damage" and e.target_id==1:absorbed+=e.absorbed
	ck(absorbed>0,"shield absorbs damage")
	# Start formation snapshots isolated from external data.
	s=Sim.new();var input=[u(1,0,Vector2i(0,3)),u(2,1,Vector2i(0,2))]
	s.configure(input);input[0].hp=99999
	ck(s.units[0].hp==100,"input mutation cannot alter core")
	var snap=s.snapshot();snap.units[0].hp=0
	ck(s.units[0].hp==100,"snapshot mutation cannot alter core")
	# Invalid reconfiguration during battle must not mutate it.
	s.start();var before=s.snapshot();ck(s.configure(input)!="","running reconfigure rejected");ck(s.snapshot()==before,"running reconfigure atomic")
	print("EDGE FAILURES=",failed);quit(1 if failed else 0)
