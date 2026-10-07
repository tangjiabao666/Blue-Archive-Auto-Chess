extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const Matchup=preload("res://core/matchup_presenter.gd")
const Icons=preload("res://scripts/native_skill_icons.gd")
var checks:=0
var failures:=0
var presenter
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func row(sim,key:String,slot:String,cap:float=5.0)->Dictionary:
	var result:Dictionary=presenter.describe(sim,key,"测试名字",3,cap)
	for skill in result.skills:
		if skill.slot==slot:return skill
	return {}
func has_all(value:String,parts:Array,label:String)->void:
	for part in parts:ck(value.contains(str(part)),label+": "+str(part))
func _initialize()->void:
	var path:="res://core/recruitment_skill_presenter.gd"
	ck(ResourceLoader.exists(path),"pure recruitment skill presenter exists")
	if not ResourceLoader.exists(path):finish();return
	presenter=load(path)
	var sim=Sim.new()
	var icons=Icons.new()
	ck(sim.active_character_keys().size()==14,"all fourteen recruitable characters are exercised")
	for key in sim.active_character_keys():
		var result:Dictionary=presenter.describe(sim,key,"中文名字",4,5.0)
		var source:Dictionary=sim.character_data(key)
		var one:Dictionary=sim.preview_unit(key,1)
		var two:Dictionary=sim.preview_unit(key,2)
		ck(result.ok and result.character_id==key and result.name=="中文名字" and result.cost==4,key+" preserves identity and caller shop price")
		ck(result.role in ["输出","坦克","治疗"],key+" has readable role")
		ck(result.weapon==source.weaponType and result.attack_type==Matchup.type_label(one.damage_type) and result.armor_type==Matchup.type_label(one.armor_type),key+" uses source weapon and canonical type labels")
		ck(is_equal_approx(result.range,one.range),key+" range is the actual preview reach")
		has_all(result.stats_text,["1★ HP %d · ATK %d"%[one.max_hp,one.damage],"2★ HP %d · ATK %d"%[two.max_hp,two.damage]],key+" actual stats")
		ck(result.enhanced_text.contains("26.6%") and result.enhanced_text.contains("已计入"),key+" enhanced shown once and not reapplied")
		has_all(result.caveat,["ATK","Heal","非最终","就绪"],key+" caveats separate coefficients and readiness")
		ck(result.skills.size()==3 and result.skills.map(func(s):return s.slot)==["ex","basic","sub"],key+" exactly three slots in display order")
		for skill in result.skills:
			ck(skill.name==source[skill.slot].name and not skill.label.is_empty(),key+" source skill name "+skill.slot)
			ck(not skill.text.is_empty() and not skill.text.contains("尚未解析"),key+" supported Chinese skill text "+skill.slot)
			ck(skill.icon_key==icons.skill_key(key,skill.slot) and not skill.icon_key.is_empty(),key+" verified skill icon "+skill.slot)
			ck(skill.text.split("\n").size()<=4,key+" card stays within four text lines "+skill.slot)
		var ex:String=result.skills[0].text
		has_all(ex,["2★","三合一","首次","就绪","冷却"],key+" EX merge and timing")
		if source.basic.trigger.kind=="periodic":has_all(row(sim,key,"basic").text,["首次5s","%ss"%str(source.basic.trigger.intervalSeconds).trim_suffix(".0")],key+" initial cap and source recurrence")
	# Semantics that a generic damage summary would misrepresent.
	has_all(row(sim,"shiroko","ex").text,["10段合计760.88% ATK"],"Shiroko aggregate drone damage")
	has_all(row(sim,"hina","ex").text,["扇形","10段合计1208.34% ATK"],"Hina aggregate fan")
	has_all(row(sim,"yuuka","basic").text,["9段合计573.82% ATK"],"Yuuka aggregate burst")
	has_all(row(sim,"serika","basic").text,["11段合计425.62% ATK"],"Serika aggregate burst")
	has_all(row(sim,"aris","ex").text,["0/1/2层","591.13%/886.69%/1182.25% ATK","择一","消耗全部"],"Aris mutually exclusive charge variants")
	has_all(row(sim,"aris","basic").text,["蓄能+1","上限2","32.37%","20s","蓄能不随增益消失"],"Aris persistent charge")
	has_all(row(sim,"aris","sub").text,["EX","0/1/2层","22.99%/34.48%/45.97%","20s","消耗前"],"Aris pre-consumption sub")
	has_all(row(sim,"iori","ex").text,["3发","各666.29% ATK","后方扇形","每发仅计一次","1998.87% ATK"],"Iori per-shot and overlap")
	has_all(row(sim,"aru","basic").text,["290.14% ATK","50%","476.85% ATK","主目标可叠加"],"Aru optional explosion")
	has_all(row(sim,"aru","ex").text,["521.25% ATK","554.87% ATK","主目标可叠加"],"Aru independent damage components")
	has_all(row(sim,"hoshino","basic").text,["低于30%","每战1次","每4s","191.13% Heal","20s","首跳4s"],"Hoshino periodic recovery without bonus tick")
	has_all(row(sim,"hoshino","sub").text,["EX","205.2% Heal","施放结束"],"Hoshino EX-only shield")
	has_all(row(sim,"tsubaki","basic").text,["低于30%","每战1次","663.63% Heal"],"Tsubaki one-time threshold heal")
	has_all(row(sim,"tsubaki","ex").text,["防御力+44.97%","30s","嘲讽6.2s"],"Tsubaki defense and taunt")
	has_all(row(sim,"tsubaki","sub").text,["换弹期间","受到伤害-45.6%"],"Tsubaki conditional reduction")
	has_all(row(sim,"koharu","basic").text,["其他队友","低于50%","最低生命比例","153.63% Heal","内置冷却20s","开战即就绪"],"Koharu excludes self and uses threshold target")
	has_all(row(sim,"koharu","ex").text,["同一圆形","友方","192.75% Heal","敌方","431.76% ATK","可含自身"],"Koharu shared healing/damage circle")
	has_all(row(sim,"koharu","sub").text,["每30s","治疗力+41%","20s"],"Koharu independent periodic healing buff")
	ck(not row(sim,"koharu","sub").text.contains("首次5s"),"basic first-delay cap never changes periodic sub")
	has_all(row(sim,"mutsuki","basic").text,["3枚","15s","每枚635.66% ATK","触发后爆炸"],"Mutsuki persistent mines rather than immediate damage")
	has_all(row(sim,"mutsuki","ex").text,["3个圆形","每区778.49% ATK","重叠","2335.47% ATK"],"Mutsuki per-area damage")
	has_all(row(sim,"haruna","ex").text,["887.19% ATK","每后续目标-10%","最低30%"],"Haruna linear falloff rather than exponential")
	has_all(row(sim,"nonomi","sub").text,["大型","12.86% ATK","逐命中"],"Nonomi explicit large target and runtime dispatch")
	has_all(row(sim,"hina","sub").text,["目标未在掩体","5.2% ATK","逐命中"],"Hina echo condition")
	has_all(row(sim,"iori","sub").text,["自身未在掩体","43.1% ATK","逐命中"],"Iori actor cover condition")
	has_all(row(sim,"shiroko","sub").text,["普攻","20%","内置冷却25s","攻击速度+57.46%","30s"],"Shiroko proc rate and cooldown")
	has_all(row(sim,"mutsuki","sub").text,["普攻","25%","内置冷却25s","命中值+57.46%","30s"],"Mutsuki proc rate and cooldown")
	has_all(row(sim,"yuuka","sub").text,["进入掩体","142.5% Heal","内置冷却10s"],"Yuuka cover-entry heal")
	has_all(row(sim,"hina","basic").text,["弹药耗尽","换弹","攻击力+39.98%","16s"],"Hina source conditional reload buff")
	for pair in [["hina","basic"],["hoshino","basic"],["tsubaki","basic"],["tsubaki","sub"],["haruna","sub"],["aru","sub"],["aris","sub"],["nonomi","sub"],["iori","sub"],["hina","sub"]]:
		ck(not row(sim,pair[0],pair[1]).text.contains("冷却"),str(pair)+" does not invent a fixed cooldown")
	has_all(presenter.describe(sim,"haruna","",2,5.0).stats_text,["静止增益已计入"],"Haruna preview explains its actual stationary ATK")
	# Mutations in this test fixture prove formatting reads live data and options.
	sim.options.ex_base_seconds=7.13;sim.options.ex_seconds_per_cost=4.27;sim.options.ex_initial_cooldown_fraction=0.333
	has_all(row(sim,"shiroko","ex").text,["首次5.25s就绪","冷却15.7s"],"EX uses actual tick-quantized preview timings")
	has_all(row(sim,"shiroko","basic",3.21).text,["首次3.25s"],"explicit basic cap follows tick quantization")
	has_all(row(sim,"shiroko","basic",0).text,["首次25s"],"zero cap preserves native first interval")
	has_all(row(sim,"shiroko","basic",99).text,["首次25s"],"cap cannot lengthen first interval")
	sim.options.hina_echo_per_hit=false
	has_all(row(sim,"hina","sub").text,["末段命中"],"conditional echo reflects configured dispatch")
	sim._characters.shiroko.basic.damage.totalAtkRatio=4.1256
	has_all(row(sim,"shiroko","basic").text,["412.56% ATK"],"coefficients are not duplicated constants")
	sim._characters.shiroko.basic.kind="future_unknown_mechanic"
	ck(row(sim,"shiroko","basic").text.contains("尚未解析"),"unknown mechanic is explicit rather than fabricated")
	var unknown:Dictionary=presenter.describe(sim,"not_a_character","误导名字",999,5)
	ck(not unknown.ok and unknown.skills.is_empty() and unknown.stats_text.is_empty(),"unknown identity fails cleanly without a fabricated unit")
	ck(not presenter.describe(sim,"serina","",1,5).ok,"inactive future support is not recruitable")
	# Snapshot a running real simulation and source before repeated inspection.
	sim=Sim.new()
	ck(sim.configure([{"id":0,"team":0,"cell":Vector2(0,1),"character_id":"aris","star":2},{"id":1,"team":1,"cell":Vector2(0,-1),"character_id":"hoshino","star":2}]).is_empty(),"read-only fixture configured")
	sim.start();sim.step()
	var before_state:Dictionary=sim.snapshot();var before_data:Dictionary=sim._data.duplicate(true);var before_events:Array=sim.events.duplicate(true);var before_initial:Array=sim._initial.duplicate(true)
	var original:Dictionary=presenter.describe(sim,"aris","爱丽丝",4,5)
	var changed:Dictionary=presenter.describe(sim,"aris","爱丽丝",4,5)
	changed.skills[0].text="mutated";changed.skills.clear()
	ck(presenter.describe(sim,"aris","爱丽丝",4,5)==original,"returned descriptions are detached")
	for key in sim.active_character_keys():presenter.describe(sim,key,"",1,5)
	ck(sim.snapshot()==before_state and sim.events==before_events and sim._initial==before_initial,"state/events/RNG/initial roster unchanged")
	ck(sim._data==before_data,"source data is unchanged")
	finish()
func finish()->void:
	print("RECRUITMENT SKILL PRESENTER ",checks," checks; ",failures," failures");quit(1 if failures else 0)
