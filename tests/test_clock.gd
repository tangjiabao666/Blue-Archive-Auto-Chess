extends SceneTree
const Clock = preload("res://core/battle_clock.gd")
var fail := 0
func ck(b:bool,s:String)->void:
	if not b: fail+=1;printerr("FAIL: "+s)
func create_clock():
	var c=Clock.new()
	c.sim.configure([{"id":1,"team":0,"cell":Vector2i(0,4)},{"id":2,"team":1,"cell":Vector2i(0,1)}])
	c.sim.start();return c
func _initialize()->void:
	var a=create_clock();var b=create_clock()
	var ea=[];var eb=[]
	for i in range(100): ea.append_array(a.advance(0.03))
	for i in range(30): eb.append_array(b.advance(0.10))
	ck(a.sim.tick==60,"clock advances fixed ticks")
	ck(ea==eb and a.sim.snapshot()==b.sim.snapshot(),"frame chunking independent")
	var old=a.sim.snapshot()
	ck(a.advance(-1).is_empty() and a.advance(NAN).is_empty() and a.advance(INF).is_empty(),"invalid delta ignored")
	ck(a.sim.snapshot()==old,"invalid delta cannot change state")
	a.reset();ck(a.accumulator==0 and a.generation==1 and a.sim.phase=="prepare","reset clears clock and increments generation")
	a.sim.start();var e=a.advance(0.5)
	ck(not e.is_empty() and e[0].generation==1,"events carry reset generation")
	var c=create_clock();c.advance(100.0)
	ck(c.sim.phase=="finished" and c.accumulator==0,"large delta finishes without leftover time")
	print("CLOCK FAILURES=",fail);quit(1 if fail else 0)
