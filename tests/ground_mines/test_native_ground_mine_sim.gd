extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const Mines=preload("res://scripts/native_ground_mines.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func feed(mines:Node3D,sim:RefCounted,events:Array,generation:int=51)->void:
 var snapshot:Dictionary=sim.snapshot()
 for original in events:
  var visual_event:Dictionary=original.duplicate(true)
  visual_event.generation=generation
  mines.consume(visual_event,sim.units)
 mines.update_time(float(sim.tick)*0.05)
 ck(sim.snapshot()==snapshot,"feeding authoritative events cannot mutate simulator")
func fixture()->RefCounted:
 var sim=Sim.new()
 sim.configure([{"id":0,"team":0,"cell":Vector2(0,2),"character_id":"mutsuki","star":1},{"id":1,"team":1,"cell":Vector2(0,-4),"character_id":"yuuka","star":1}],{"random_damage":false})
 sim.start();sim.tick=10
 for unit in sim.units:
  unit.basic_ready=100000;unit.skill_ready=100000;unit.attack_ready=100000;unit.aim_ready=100000;unit.aimed=true;unit.busy_until=100000
 return sim
func run()->void:
 var mines:=Mines.new();root.add_child(mines);mines.reset(51)
 var sim=fixture();sim._try_skill(sim.units[0],"basic")
 for index in range(41):feed(mines,sim,sim.step())
 ck(sim.snapshot().mines.size()==3,"real Mutsuki basic creates three authoritative mines")
 ck(mines.diagnostics().active_mines==3,"all three real simulator placements render")
 var native:Dictionary=mines.snapshot()
 for mine in sim.snapshot().mines:
  ck(native.has(mine.id) and native[mine.id].cell==mine.cell,"rendered mine cell matches actual simulator mine")
  ck(native[mine.id].expires_tick==mine.expires,"rendered lifetime follows source-owned expiry tick")
 sim.phase="paused"
 var before:Dictionary=mines.snapshot();var paused:Array=sim.step();feed(mines,sim,paused)
 ck(paused.is_empty() and mines.snapshot()==before,"actual simulator pause freezes mine visuals")
 sim.phase="running"
 var mine_id:int=int(sim.snapshot().mines[1].id)
 sim.units[1].cell=sim.snapshot().mines[1].cell;sim.units[1].max_hp=1000000;sim.units[1].hp=1000000
 feed(mines,sim,sim.step())
 ck(sim.snapshot().mines.size()==2 and mines.diagnostics().active_mines==2,"actual mine trigger removes only one visual")
 ck(not mines.snapshot().has(mine_id),"triggered native mesh is gone")
 sim.units[1].cell=Vector2(0,-4)
 for index in range(301):feed(mines,sim,sim.step())
 ck(sim.snapshot().mines.is_empty() and mines.get_child_count()==0,"actual source expiry frees every native mine")
 mines.reset(51);sim=fixture();sim._try_skill(sim.units[0],"basic")
 for index in range(41):feed(mines,sim,sim.step())
 ck(mines.diagnostics().active_mines==3,"fresh actual round reuses mine identifiers")
 sim.units[0].hp=0
 feed(mines,sim,sim.step())
 ck(sim.snapshot().mines.is_empty() and mines.get_child_count()==0,"actual dead-owner cleanup releases every native mine")
 ck(mines.diagnostics().finished,"actual finished event closes presenter")
 mines.free()
 print("NATIVE_GROUND_MINE_SIM ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
