extends SceneTree
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr(label)
func _initialize():
	ck(ResourceLoader.exists("res://core/combat_status_presenter.gd"),"combat status presenter exists")
	if fails:quit(1);return
	var presenter=load("res://core/combat_status_presenter.gd").new()
	var sim=load("res://core/character_sim.gd").new()
	var u=sim.preview_unit("shiroko",1)
	var state=presenter.present(u,0,sim.character_data("shiroko"),false)
	ck(state.ex.kind=="locked","one-star EX shows locked")
	u.star=2;u.skill_ready=100;u.skill_cooldown_ticks=500
	state=presenter.present(u,40,sim.character_data("shiroko"),false)
	ck(state.ex.remaining_seconds==3.0 and state.ex.kind=="cooldown","EX uses actual ready tick")
	state=presenter.present(u,101,sim.character_data("shiroko"),false)
	ck(state.ex.kind=="ready","elapsed EX is ready")
	u.buffs={"attack":{"stat":"AttackPower","fraction":0.2,"until":200},"expired":{"stat":"AttackSpeed","fraction":0.3,"until":30}}
	u.shield=500;u.shield_until=90;u.stun_until=60;u.charges=2
	state=presenter.present(u,40,sim.character_data("shiroko"),false)
	ck(state.effects[0].hint.contains("攻击力"),"buff tooltip translates stat name")
	ck(state.effects.size()==4,"active buff shield stun and charge are visible")
	ck(state.effects.filter(func(x):return x.id=="expired").is_empty(),"expired buff omitted")
	var dead=u.duplicate(true);dead.hp=0
	ck(not presenter.present(dead,40,sim.character_data("shiroko"),false).visible,"dead unit hides all statuses")
	var h=sim.preview_unit("hoshino",2)
	state=presenter.present(h,0,sim.character_data("hoshino"),false)
	ck(state.basic.kind=="condition" and state.basic.remaining_seconds==0,"HP-trigger basic has no invented CD")
	h.basic_activations=1
	ck(presenter.present(h,0,sim.character_data("hoshino"),false).basic.kind=="used","one-use heal shows spent")
	var n=sim.preview_unit("hina",2)
	ck(presenter.present(n,0,sim.character_data("hina"),false).basic.kind=="condition","reload trigger is conditional")
	ck(presenter.present(u,40,sim.character_data("shiroko"),true).ex.kind=="preparation","preparation doesn't count down")
	u.sub_ready=140
	state=presenter.present(u,40,sim.character_data("shiroko"),false)
	ck(state.has("sub"),"sub-skill has independent display state")
	if state.has("sub"):
		ck(state.sub.remaining_seconds==5.0,"sub-skill internal CD is separate from basic and EX")
		ck(presenter.present(h,0,sim.character_data("hoshino"),false).sub.kind=="condition","EX-triggered sub has no invented countdown")
	var healer_definition={"basic":{"trigger":{"kind":"ally_hp_below_threshold","thresholdHpRatio":0.5,"internalCooldownSeconds":20}},"sub":{"trigger":{"kind":"periodic","intervalSeconds":30}}}
	u.basic_ready=140;u.sub_ready=600
	state=presenter.present(u,40,healer_definition,false)
	ck(state.basic.kind=="cooldown" and state.basic.remaining_seconds==5.0,"ally threshold basic exposes actual internal CD")
	ck(state.sub.kind=="cooldown" and state.sub.remaining_seconds==28.0,"periodic sub exposes independent interval")
	print("COMBAT STATUS FAILURES=",fails);quit(1 if fails else 0)
