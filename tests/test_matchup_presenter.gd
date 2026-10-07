extends SceneTree
const Sim=preload("res://core/character_sim.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:
	var path:="res://core/matchup_presenter.gd"
	ck(ResourceLoader.exists(path),"pure matchup presenter exists")
	if not ResourceLoader.exists(path):finish();return
	var presenter=load(path)
	var sim=Sim.new()
	var damage_types:Array=["Explosion","Pierce","Mystic"]
	var armor_types:Array=["LightArmor","HeavyArmor","Unarmed"]
	var unit:Dictionary=sim.preview_unit("shiroko")
	var result:Dictionary=presenter.describe(sim,unit,damage_types,armor_types)
	ck(result.attack_name=="爆发" and result.armor_name=="轻装甲","source types have readable localized labels")
	ck(result.outgoing==[{"type":"LightArmor","label":"轻装甲","multiplier":2.0},{"type":"HeavyArmor","label":"重装甲","multiplier":1.0},{"type":"Unarmed","label":"特殊装甲","multiplier":0.5}],"outgoing factors describe attacker damage against each armor")
	ck(result.incoming==[{"type":"Explosion","label":"爆发","multiplier":2.0},{"type":"Pierce","label":"贯穿","multiplier":0.5},{"type":"Mystic","label":"神秘","multiplier":1.0}],"incoming factors describe each damage type against inspected armor")
	ck(result.outgoing_text=="对装甲：轻装甲 ×2 / 重装甲 ×1 / 特殊装甲 ×0.5","outgoing text is concise and retains fractional factors")
	ck(result.incoming_text=="承伤：爆发 ×2 / 贯穿 ×0.5 / 神秘 ×1","incoming text identifies received damage rather than outgoing power")
	ck(result.caveat=="属性倍率，非最终伤害；不指定攻击目标","caption distinguishes type factors from final damage and targeting")
	ck(result.text=="攻击 爆发 · 防御 轻装甲\n"+result.outgoing_text+"\n"+result.incoming_text+"\n"+result.caveat,"complete text composes the same authoritative fields")
	for key in sim.active_character_keys():
		var actor:Dictionary=sim.preview_unit(key)
		var description:Dictionary=presenter.describe(sim,actor,damage_types,armor_types)
		ck(description.attack_name==presenter.type_label(actor.damage_type) and description.armor_name==presenter.type_label(actor.armor_type),key+" uses current source types")
		for row in description.outgoing:ck(is_equal_approx(row.multiplier,sim.type_multiplier(actor.damage_type,row.type)),key+" outgoing matches simulation")
		for row in description.incoming:ck(is_equal_approx(row.multiplier,sim.type_multiplier(row.type,actor.armor_type)),key+" incoming matches simulation")
	var all_damage:Array=["Normal","Explosion","Pierce","Mystic","Sonic","FutureDamage"]
	var all_armor:Array=["LightArmor","HeavyArmor","Unarmed","Structure","ElasticArmor","Normal","FutureArmor"]
	for damage in all_damage:
		for armor in all_armor:
			var description:Dictionary=presenter.describe(sim,{"damage_type":damage,"armor_type":armor},all_damage,all_armor)
			for row in description.outgoing:ck(is_equal_approx(row.multiplier,sim.type_multiplier(damage,row.type)),damage+" outgoing matrix uses effective runtime value")
			for row in description.incoming:ck(is_equal_approx(row.multiplier,sim.type_multiplier(row.type,armor)),armor+" incoming matrix uses effective runtime value")
	result=presenter.describe(sim,{"damage_type":"Sonic","armor_type":"ElasticArmor"},["Sonic"],["Unarmed","Structure","ElasticArmor"])
	ck(result.outgoing_text=="对装甲：特殊装甲 ×1.5 / 结构装甲 ×1 / 弹性装甲 ×2","Sonic fractions and runtime Structure override are displayed without rounding")
	ck(result.incoming_text=="承伤：振动 ×2","Elastic armor does not inherit a generic triangle")
	ck(presenter.type_label("Normal")=="普通" and presenter.type_label("FutureDamage")=="FutureDamage","normal and unknown names remain readable without invented taxonomy")
	ck(presenter.type_label("")=="未知","missing type label has explicit unknown text")
	result=presenter.describe(sim,unit,["Mystic","Explosion","Mystic","Pierce"],["Unarmed","LightArmor","Unarmed","HeavyArmor"])
	ck(result.incoming.map(func(row):return row.type)==["Mystic","Explosion","Pierce"],"damage types retain caller order with stable deduplication")
	ck(result.outgoing.map(func(row):return row.type)==["Unarmed","LightArmor","HeavyArmor"],"armor types retain caller order with stable deduplication")
	result=presenter.describe(sim,unit,[],[])
	ck(result.outgoing.is_empty() and result.incoming.is_empty(),"empty active lists invent no recruitable types")
	ck(result.outgoing_text.is_empty() and result.incoming_text.is_empty(),"empty relations do not display dangling headings")
	ck(result.text=="攻击 爆发 · 防御 轻装甲\n"+result.caveat,"empty relations keep a clean compact description")
	# Deliberately changed fixture data detects a copied multiplier table or cache.
	sim._data.typeEffectivenessRaw.Explosion.LightArmor=12500
	result=presenter.describe(sim,unit,damage_types,armor_types)
	ck(is_equal_approx(result.outgoing[0].multiplier,1.25) and result.outgoing_text.contains("轻装甲 ×1.25"),"current runtime values are queried and formatted without a duplicate table")
	var before_unit:Dictionary=unit.duplicate(true)
	var before_damage:Array=damage_types.duplicate(true)
	var before_armor:Array=armor_types.duplicate(true)
	var before_state:Dictionary=sim.snapshot()
	var before_data:Dictionary=sim._data.duplicate(true)
	var before_rng:int=sim._rng.state
	var original:Dictionary=presenter.describe(sim,unit,damage_types,armor_types)
	result=presenter.describe(sim,unit,damage_types,armor_types)
	result.outgoing[0].multiplier=99.0;result.incoming.clear();result.text="mutated"
	for _i in range(3):ck(presenter.describe(sim,unit,damage_types,armor_types)==original,"returned relations and subsequent descriptions are detached")
	ck(unit==before_unit and damage_types==before_damage and armor_types==before_armor,"formatting preserves all caller inputs")
	ck(sim.snapshot()==before_state and sim._data==before_data and sim._rng.state==before_rng,"inspection changes no simulation state, source data or RNG")
	finish()
func finish()->void:
	print("MATCHUP PRESENTER ",checks," checks; ",failures," failures");quit(1 if failures else 0)
