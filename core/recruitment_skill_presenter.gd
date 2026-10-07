extends RefCounted
## Recruitment-only projection: reads detached definitions and preview units.
## Never applies an effect, advances combat, changes options, or rolls RNG.
const Sim=preload("res://core/character_sim.gd")
const Matchup=preload("res://core/matchup_presenter.gd")
const Icons=preload("res://scripts/native_skill_icons.gd")
const ROLES={"damage_dealer":"输出","tank":"坦克","healer":"治疗"}
const STATS={"MaxHP":"生命上限","AttackPower":"攻击力","DefensePower":"防御力","HealPower":"治疗力","AttackSpeed":"攻击速度","CriticalPoint":"暴击值","CriticalDamageRate":"暴击伤害","AccuracyPoint":"命中值","DodgePoint":"闪避值"}
const LABELS={"ex":"EX技能","basic":"普通技能","sub":"子技能"}
const CAVEAT:="ATK=攻击力，Heal=治疗力；系数非最终伤害/治疗。就绪后仍需有效目标与动作空档；自动选区与派发为本作适配。"
const UNKNOWN:="尚未解析此技能机制"

static func describe(sim,key:String,display_name:String,cost:int,initial_basic_delay_cap_seconds:float)->Dictionary:
	var result:Dictionary={"ok":false,"character_id":key,"name":"","cost":cost,"role":"","weapon":"","attack_type":"","armor_type":"","range":0.0,"stats_text":"","enhanced_text":"","skills":[],"caveat":"未找到可招募角色"}
	if sim==null or key not in sim.active_character_keys():return result
	var source:Dictionary=sim.character_data(key)
	var one:Dictionary=sim.preview_unit(key,1)
	var two:Dictionary=sim.preview_unit(key,2)
	if source.is_empty() or one.is_empty() or two.is_empty():return result
	result.ok=true
	result.name=display_name if not display_name.is_empty() else str(source.get("displayName",key))
	result.role=ROLES.get(source.get("role",""),"未知定位")
	result.weapon=str(one.weapon)
	result.attack_type=Matchup.type_label(one.damage_type)
	result.armor_type=Matchup.type_label(one.armor_type)
	result.range=float(one.range)
	result.stats_text="1★ HP %d · ATK %d\n2★ HP %d · ATK %d"%[one.max_hp,one.damage,two.max_hp,two.damage]
	if source.sub.trigger.kind=="while_stationary" and one.buffs.get(key+"_stationary",{}).get("until",0)>sim.tick:
		result.stats_text+="（静止增益已计入）"
	var enhanced:Dictionary=source.get("enhanced",{})
	result.enhanced_text="常驻强化：%s（已计入预览数值）"%_buff(enhanced) if enhanced.get("trigger",{}).get("kind","")=="always" else UNKNOWN
	result.caveat=CAVEAT
	var icons=Icons.new()
	for slot in ["ex","basic","sub"]:
		var skill:Dictionary=source.get(slot,{})
		var effect:String=_effect_text(skill,key,sim.options)
		var trigger:String=_trigger_text(skill,slot,two,initial_basic_delay_cap_seconds)
		var lines:PackedStringArray=[]
		if slot!="ex" and not trigger.is_empty():lines.append(trigger)
		lines.append(effect)
		if slot=="ex":lines.append(trigger)
		result.skills.append({"slot":slot,"label":LABELS[slot],"name":str(skill.get("name","未知技能")),"text":"\n".join(lines),"icon_key":icons.skill_key(key,slot)})
	return result

static func _trigger_text(skill:Dictionary,slot:String,two:Dictionary,cap:float)->String:
	if slot=="ex":
		return "1★三合一升2★解锁 · 首次%ss就绪 · 冷却%ss"%[_n(float(two.skill_ready)*Sim.STEP_SECONDS),_n(float(two.skill_cooldown_ticks)*Sim.STEP_SECONDS)]
	var trigger:Dictionary=skill.get("trigger",{})
	var text:String
	match str(trigger.get("kind","")):
		"periodic":
			var interval:float=float(trigger.intervalSeconds)
			text="每%ss"%_n(interval)
			if slot=="basic":
				var initial:float=minf(interval,cap) if is_finite(cap) and cap>0 else interval
				var ticks:int=maxi(1,ceili(initial/Sim.STEP_SECONDS-0.00000001))
				text+=" · 首次%ss就绪"%_n(ticks*Sim.STEP_SECONDS)
		"hp_below_threshold":text="自身生命低于%s · 每战%d次"%[_pct(trigger.thresholdHpRatio),int(trigger.activationLimitPerBattle)]
		"ally_hp_below_threshold":text="其他队友生命低于%s · 开战即就绪"%_pct(trigger.thresholdHpRatio)
		"ammo_empty":text="弹药耗尽开始换弹时"
		"normal_attack_proc":text="每轮普攻%s概率触发"%_pct(trigger.probability)
		"on_ex_cast":text="施放EX时"
		"take_cover":text="进入掩体时"
		"while_reloading":text="换弹期间"
		"while_stationary":text="静止时生效，移动即失效"
		"on_attack_damage":
			if trigger.get("targetNotInCover",false):text="命中且目标未在掩体时"
			elif trigger.get("selfNotInCover",false):text="命中且自身未在掩体时"
			elif trigger.get("targetSize","")=="large":text="命中明确标记为大型的敌人时"
			else:text=UNKNOWN
		_:text=UNKNOWN
	if trigger.has("internalCooldownSeconds"):
		text+=" · 内置冷却%ss"%_n(float(trigger.internalCooldownSeconds))
	return text

static func _effect_text(skill:Dictionary,key:String,options:Dictionary)->String:
	match str(skill.get("kind","")):
		"aoe_damage":return "圆形范围内每敌%s"%_damage(skill.damage)
		"drone_damage":return "无人机攻击单体，%s"%_damage(skill.damage)
		"single_target_burst":return "攻击单体，%s"%_damage(skill.damage)
		"fan_damage":return "前方扇形内每敌%s"%_damage(skill.damage)
		"fan_damage_knockback_stun":
			var control:String="末段眩晕" if options.get("hoshino_stun_on_final_hit",true) else "每段眩晕"
			return "前方扇形内每敌%s\n每段击退；本作%s%ss（受抗性影响）"%[_damage(skill.damage),control,_n(skill.stunSeconds)]
		"direct_shot_then_optional_explosion","direct_shot_then_explosion":
			var chance:String="%s概率爆炸"%_pct(skill.explosionProbability) if float(skill.explosionProbability)<1.0 else "圆形爆炸"
			return "单体%s；%s%s\n主目标可叠加直击与爆炸"%[_atk(skill.direct.totalAtkRatio),chance,_atk(skill.explosion.totalAtkRatio)]
		"self_regeneration":
			return "每%ss回复自身%s，持续%ss\n本作首跳%ss，无立即额外回复"%[_n(skill.tickSeconds),_heal(skill.healPowerRatioPerTick),_n(skill.durationSeconds),_n(skill.tickSeconds)]
		"self_heal_once":return "回复自身%s"%_heal(skill.healPowerRatio)
		"self_heal_on_cover":return "回复自身%s"%_heal(skill.healPowerRatio)
		"ally_threshold_heal":return "本作选范围内最低生命比例队友（不含自身）\n回复%s"%_heal(skill.healPowerRatio)
		"circle_heal_and_damage":return "同一圆形：友方回复%s（可含自身）\n敌方受到%s"%[_heal(skill.healPowerRatio),_atk(skill.damage.totalAtkRatio)]
		"self_barrier":
			var duration:String="至本次EX施放结束" if skill.get("expires","")=="when_EX_cast_ends" else "持续%ss"%_n(skill.durationSeconds)
			return "自身护盾%s，%s"%[_heal(skill.barrierHealPowerRatio),duration]
		"directional_dash_and_self_buffs":return "向目标方向冲刺（本作选位）；%s%s\n仅实际冲刺位移期间%s+%s"%[_buff(skill),_duration(skill),_stat(skill.evasion.stat),_pct(skill.evasion.bonusFraction)]
		"self_buff","conditional_self_buff":return _buff(skill)+_duration(skill)
		"reload_and_self_buff":return "换弹并补满弹药；%s%s"%[_buff(skill),_duration(skill)]
		"gain_charge_and_self_buff":return "蓄能+%d（上限%d）；%s，持续%ss\n蓄能不随增益消失"%[int(skill.energyChargeAdded),int(skill.maximumEnergyCharges),_buff(skill),_n(skill.buffDurationSeconds)]
		"charge_scaled_self_buff":return "读取消耗前0/1/2层：%s+%s\n持续%ss"%[_stat(skill.stat),_variants(skill.bonusFractionByChargeCount),_n(skill.durationSeconds)]
		"charge_scaled_line_damage":return "直线每敌，0/1/2层：%s ATK\n三者择一；施放消耗全部蓄能"%_variants(skill.damageAtkRatioByChargeCount)
		"three_shot_target_then_rear_fan":return "目标及后方扇形，%d发各%s\n每敌每发仅计一次；全中%s"%[int(skill.shotCount),_atk(skill.damagePerShot.totalAtkRatio),_atk(skill.maximumAtkRatioIfAllShotsHit)]
		"conditional_echo_damage":
			var option:String={"hina":"hina_echo_per_hit","iori":"iori_echo_per_hit","nonomi":"nonomi_echo_per_hit"}.get(key,"")
			if option.is_empty():return UNKNOWN
			var dispatch:String="逐命中" if options.get(option,true) else "末段命中"
			return "追加%s；本作%s派发"%[_atk(skill.echoAtkRatio),dispatch]
		"conditional_damage_taken_reduction":return "受到伤害-%s"%_pct(skill.damageTakenReductionFraction)
		"self_defense_buff_and_aoe_taunt":return "%s，持续%ss\n周围圆形嘲讽%ss（受抗性影响）"%[_buff(skill),_n(skill.durationSeconds),_n(skill.tauntSeconds)]
		"place_persistent_mines":return "前方布置%d枚地雷，存续%ss；触发后爆炸\n每枚%s；位置与触发范围为本作适配"%[int(skill.mineCount),_n(skill.lifetimeSeconds),_atk(skill.damagePerMine.totalAtkRatio)]
		"three_circle_damage":return "%d个圆形爆炸，每区%s\n重叠可叠加，全中上限%s"%[int(skill.areaCount),_atk(skill.damagePerArea.totalAtkRatio),_atk(skill.maximumAtkRatioIfAllAreasHit)]
		"line_damage_with_target_falloff":return "直线贯穿，首敌%s\n每后续目标-%s（按首敌系数），最低%s"%[_atk(skill.damage.totalAtkRatio),_pct(skill.damageReductionPerSubsequentTarget),_pct(skill.minimumDamageFraction)]
	return UNKNOWN

static func _damage(value:Dictionary)->String:
	var count:int=int(value.get("hitCount",1))
	return "%d段合计%s"%[count,_atk(value.totalAtkRatio)] if count>1 else _atk(value.totalAtkRatio)

static func _buff(skill:Dictionary)->String:
	if not skill.has("stat") or not skill.has("bonusFraction"):return UNKNOWN
	return "%s+%s"%[_stat(skill.stat),_pct(skill.bonusFraction)]

static func _duration(skill:Dictionary)->String:
	if skill.get("expires","")=="when_EX_cast_ends":return "，至本次EX施放结束"
	if skill.has("durationSeconds"):return "，持续%ss"%_n(skill.durationSeconds)
	return ""

static func _stat(key:String)->String:
	return STATS.get(key,key)

static func _variants(values:Dictionary)->String:
	return "%s/%s/%s"%[_pct(values["0"]),_pct(values["1"]),_pct(values["2"])]

static func _atk(ratio:float)->String:
	return _pct(ratio)+" ATK"

static func _heal(ratio:float)->String:
	return _pct(ratio)+" Heal"

static func _pct(ratio:float)->String:
	return _n(ratio*100.0)+"%"

static func _n(value:float)->String:
	return ("%.2f"%value).trim_suffix("0").trim_suffix("0").trim_suffix(".")
