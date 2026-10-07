extends SceneTree
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr(label)
func _initialize():call_deferred("run")
func run():
	ck(ResourceLoader.exists("res://scripts/combat_status_strip.gd"),"combat status strip exists")
	if fails:quit(1);return
	var strip=load("res://scripts/combat_status_strip.gd").new();root.add_child(strip)
	var sim=load("res://core/character_sim.gd").new();var u=sim.preview_unit("yuuka",2)
	strip.update_unit(u,40,sim.character_data("yuuka"),false)
	ck(strip.status.ex.kind=="cooldown","strip reflects actual EX clock")
	var revisions:int=strip.revisions
	strip.update_unit(u,40,sim.character_data("yuuka"),false)
	ck(strip.revisions==revisions,"same snapshot avoids repeated redraw work")
	u.shield=123;u.shield_until=100;strip.update_unit(u,40,sim.character_data("yuuka"),false)
	ck(strip.tooltip_text.contains("123"),"tooltip includes authoritative shield value")
	u.hp=0;strip.update_unit(u,40,sim.character_data("yuuka"),false)
	ck(not strip.visible,"dead actors hide status strip")
	strip.queue_free();await process_frame
	print("COMBAT STATUS STRIP FAILURES=",fails);quit(1 if fails else 0)
