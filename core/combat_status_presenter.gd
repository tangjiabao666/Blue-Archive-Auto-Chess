extends RefCounted
## Read-only status projection. Countdown is authoritative simulation time, not wall time.
const STEP:=0.05
const LABELS={"AttackPower":"攻","AttackSpeed":"速","CriticalPoint":"暴","CriticalDamageRate":"爆","DefensePower":"防","DodgePoint":"闪","HealPower":"疗","AccuracyPoint":"命","DamageTakenReduction":"减"}
const STAT_NAMES={"AttackPower":"攻击力","AttackSpeed":"攻击速度","CriticalPoint":"暴击值","CriticalDamageRate":"暴击伤害","DefensePower":"防御力","DodgePoint":"闪避值","HealPower":"治疗力","AccuracyPoint":"命中值","DamageTakenReduction":"受到伤害减免"}
func present(unit:Dictionary,tick:int,definition:Dictionary,preparation:bool=false)->Dictionary:
	var result={"visible":int(unit.get("hp",0))>0,"ex":{},"basic":{},"sub":{},"effects":[]}
	result.ex=_cooldown("EX",int(unit.get("skill_ready",0)),int(unit.get("skill_cooldown_ticks",1)),tick)
	if int(unit.get("star",1))<2:result.ex={"label":"EX","kind":"locked","text":"锁","remaining_seconds":0.0,"progress":0.0,"hint":"二星解锁 EX，自动释放"}
	elif preparation:result.ex={"label":"EX","kind":"preparation","text":"待战","remaining_seconds":0.0,"progress":0.0,"hint":"战斗开始后按独立冷却自动释放"}
	var trigger:Dictionary=definition.get("basic",{}).get("trigger",{})
	match str(trigger.get("kind","")):
		"periodic":
			result.basic=_cooldown("小",int(unit.get("basic_ready",0)),maxi(1,int(ceil(float(trigger.get("intervalSeconds",1))/STEP))),tick)
			if preparation:result.basic={"label":"小","kind":"preparation","text":"待战","remaining_seconds":0.0,"progress":0.0,"hint":"周期小技能，进入战斗后计时"}
		"hp_below_threshold":
			var used:bool=int(unit.get("basic_activations",0))>=int(trigger.get("activationLimitPerBattle",1))
			result.basic={"label":"小","kind":"used" if used else "condition","text":"已用" if used else "低血","remaining_seconds":0.0,"progress":0.0,"hint":"本场已触发" if used else "生命低于 %d%% 时触发"%int(float(trigger.get("thresholdHpRatio",0))*100)}
		"ammo_empty":result.basic={"label":"小","kind":"condition","text":"换弹","remaining_seconds":0.0,"progress":0.0,"hint":"弹药耗尽、开始换弹时触发，不是固定冷却"}
		_:result.basic={"label":"小","kind":"condition","text":"条件","remaining_seconds":0.0,"progress":0.0,"hint":"按角色触发条件生效"}
	result.sub=_sub_status(unit,tick,definition.get("sub",{}),preparation)
	if trigger.has("internalCooldownSeconds") and int(unit.get("basic_ready",0))>tick and not preparation:
		result.basic=_cooldown("小",int(unit.basic_ready),maxi(1,int(ceil(float(trigger.internalCooldownSeconds)/STEP))),tick)
	elif str(trigger.get("kind",""))=="ally_hp_below_threshold":
		result.basic={"label":"小","kind":"condition","text":"队友","remaining_seconds":0.0,"progress":0.0,"hint":"其他队友生命低于 %d%% 时触发，不以自身为目标"%int(float(trigger.get("thresholdHpRatio",0.5))*100)}
	var buffs:Dictionary=unit.get("buffs",{})
	var ids:Array=buffs.keys();ids.sort()
	for id in ids:
		var buff:Dictionary=buffs[id];var until:int=int(buff.get("until",0))
		if until<=tick:continue
		var stat:String=str(buff.get("stat",""));var fraction:float=float(buff.get("fraction",0))
		var condition:String=str(buff.get("condition",""))
		var hint:String="%s %+.0f%% · 剩余 %.1f 秒"%[STAT_NAMES.get(stat,stat),fraction*100,(until-tick)*STEP]
		if not condition.is_empty():hint="%s %+.0f%% · %s 时生效"%[STAT_NAMES.get(stat,stat),fraction*100,"静止" if condition=="while_stationary" else "换弹" if condition=="while_reloading" else "条件满足"]
		var label:String=str(LABELS.get(stat,"益"))
		# Preserve legacy projections; only Asuna's distinct runtime buff IDs carry these labels.
		if str(unit.get("character_id",""))=="asuna":
			if str(id)=="asuna_ex_attack_speed" and stat=="AttackSpeed":
				label="EX";hint="EX · 攻击速度 %+.2f%% · 剩余 %.1f 秒"%[fraction*100,(until-tick)*STEP]
			elif str(id)=="asuna_sub_attack_speed" and stat=="AttackSpeed":
				label="子";hint="子技能 · 攻击速度 %+.2f%% · 剩余 %.1f 秒"%[fraction*100,(until-tick)*STEP]
			elif str(id)=="asuna_ex_dash_evasion" and stat=="DodgePoint":
				hint="EX 冲刺 · 闪避值 %+.2f%% · 仅冲刺位移期间 · 剩余 %.1f 秒"%[fraction*100,(until-tick)*STEP]
		result.effects.append({"id":str(id),"label":label,"kind":"buff" if fraction>=0 else "debuff","seconds":(until-tick)*STEP if condition.is_empty() else 0.0,"hint":hint})
	if int(unit.get("shield",0))>0 and int(unit.get("shield_until",0))>tick:
		result.effects.append({"id":"shield","label":"盾","kind":"shield","seconds":(int(unit.shield_until)-tick)*STEP,"hint":"护盾 %d · 剩余 %.1f 秒"%[unit.shield,(int(unit.shield_until)-tick)*STEP]})
	if int(unit.get("stun_until",0))>tick:
		result.effects.append({"id":"stun","label":"晕","kind":"debuff","seconds":(int(unit.stun_until)-tick)*STEP,"hint":"眩晕 · 剩余 %.1f 秒"%((int(unit.stun_until)-tick)*STEP)})
	if int(unit.get("taunt_until",0))>tick:
		result.effects.append({"id":"taunt","label":"嘲","kind":"debuff","seconds":(int(unit.taunt_until)-tick)*STEP,"hint":"受到嘲讽 · 剩余 %.1f 秒"%((int(unit.taunt_until)-tick)*STEP)})
	if int(unit.get("charges",0))>0:
		result.effects.append({"id":"charge","label":str(unit.charges),"kind":"charge","seconds":0.0,"hint":"当前蓄能 %d 层"%unit.charges})
	var cover:Dictionary=unit.get("cover_status",{})
	if not preparation and cover.get("state","none") in ["protected","exposed"]:
		var protected:bool=cover.state=="protected"
		var hint:String="面向最近敌人的直射方向：掩体减伤 %d%%"%int(round((1.0-float(cover.get("multiplier",1.0)))*100)) if protected else "侧后方暴露：掩体未挡住最近敌人的直射方向"
		hint+="；其他方向需单独判断，抛射与穿透技能无视此保护"
		result.effects.append({"id":"terrain_cover","label":"掩" if protected else "露","kind":"cover" if protected else "exposed","seconds":0.0,"hint":hint})
	return result
func _cooldown(label:String,ready:int,duration:int,tick:int)->Dictionary:
	var seconds:float=maxi(0,ready-tick)*STEP
	return {"label":label,"kind":"ready" if seconds<=0 else "cooldown","text":"就绪" if seconds<=0 else "%ds"%int(ceil(seconds)),"remaining_seconds":seconds,"progress":clampf(1.0-float(ready-tick)/maxi(1,duration),0.0,1.0),"hint":"%s 就绪，等待有效目标与动作空档"%label if seconds<=0 else "%s 冷却剩余 %.1f 秒"%[label,seconds]}

func _sub_status(unit:Dictionary,tick:int,skill:Dictionary,preparation:bool)->Dictionary:
	var trigger:Dictionary=skill.get("trigger",{})
	var kind:String=str(trigger.get("kind",""))
	if kind=="periodic":
		var result:Dictionary=_cooldown("子",int(unit.get("sub_ready",0)),maxi(1,int(ceil(float(trigger.get("intervalSeconds",1))/STEP))),tick)
		if preparation:result={"label":"子","kind":"preparation","text":"待战","remaining_seconds":0.0,"progress":0.0,"hint":"周期子技能，进入战斗后计时"}
		return result
	var names:Dictionary={"normal_attack_proc":"普攻","take_cover":"掩体","on_ex_cast":"EX","on_attack_damage":"攻击","always":"常驻","while_stationary":"静止","while_reloading":"换弹"}
	var hint:String={"normal_attack_proc":"普攻命中后按角色概率触发","take_cover":"满足掩体条件时触发","on_ex_cast":"施放 EX 时触发","on_attack_damage":"满足攻击命中条件时触发","always":"常驻被动，无冷却","while_stationary":"保持静止时生效","while_reloading":"换弹期间生效"}.get(kind,"满足角色子技能条件时触发")
	if trigger.has("internalCooldownSeconds"):
		var ready:int=int(unit.get("cover_ready" if kind=="take_cover" else "sub_ready",0))
		var result:Dictionary=_cooldown("子",ready,maxi(1,int(ceil(float(trigger.internalCooldownSeconds)/STEP))),tick)
		if result.kind=="cooldown" and not preparation:result.hint+="；"+hint;return result
	return {"label":"子","kind":"condition","text":names.get(kind,"条件"),"remaining_seconds":0.0,"progress":0.0,"hint":hint}
