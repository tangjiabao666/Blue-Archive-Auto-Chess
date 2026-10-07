extends SceneTree
var failures:=0
var checks:=0
func ck(value:bool,label:String):
 checks+=1
 if not value:failures+=1;printerr("FAIL ",label)
func _initialize():call_deferred("run")
func run():
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=false;root.add_child(app);app.set_process(false)
 app.session.clock.sim.phase="finished"
 ck(app._battle_status_text().contains("正在结算其他对局"),"visible battle completion explains cooperative settlement wait")
 app.session.clock.sim.phase="running"
 ck(app._battle_status_text().contains("自动战斗"),"ordinary combat status remains unchanged")
 app.free();print("COOPERATIVE UI ",checks," checks; ",failures," failures");quit(1 if failures else 0)
