extends RefCounted
## Read-only type descriptions. Effective factors belong to CharacterSim,
## including its Structure override; this presenter owns no matchup table.
const TYPE_LABELS={"Normal":"普通","Explosion":"爆发","Pierce":"贯穿","Mystic":"神秘","Sonic":"振动",
	"LightArmor":"轻装甲","HeavyArmor":"重装甲","Unarmed":"特殊装甲","Structure":"结构装甲","ElasticArmor":"弹性装甲"}
const CAVEAT:="属性倍率，非最终伤害；不指定攻击目标"

static func type_label(key:String)->String:
	return TYPE_LABELS.get(key,key) if not key.is_empty() else "未知"

static func describe(sim,unit:Dictionary,available_damage_types:Array,available_armor_types:Array)->Dictionary:
	var attack_type:String=str(unit.get("damage_type",""))
	var armor_type:String=str(unit.get("armor_type",""))
	var outgoing:Array=[]
	var incoming:Array=[]
	for key in _unique_types(available_armor_types):
		outgoing.append({"type":key,"label":type_label(key),"multiplier":sim.type_multiplier(attack_type,key)})
	for key in _unique_types(available_damage_types):
		incoming.append({"type":key,"label":type_label(key),"multiplier":sim.type_multiplier(key,armor_type)})
	var outgoing_text:String=_relation_text("对装甲",outgoing)
	var incoming_text:String=_relation_text("承伤",incoming)
	var lines:PackedStringArray=["攻击 %s · 防御 %s"%[type_label(attack_type),type_label(armor_type)]]
	if not outgoing_text.is_empty():lines.append(outgoing_text)
	if not incoming_text.is_empty():lines.append(incoming_text)
	lines.append(CAVEAT)
	return {"attack_name":type_label(attack_type),"armor_name":type_label(armor_type),"outgoing":outgoing,"incoming":incoming,
		"outgoing_text":outgoing_text,"incoming_text":incoming_text,"text":"\n".join(lines),"caveat":CAVEAT}

static func _unique_types(values:Array)->Array:
	var result:Array=[]
	for value in values:
		var key:String=str(value)
		if key not in result:result.append(key)
	return result

static func _relation_text(heading:String,rows:Array)->String:
	var parts:PackedStringArray=[]
	for row in rows:parts.append("%s ×%s"%[row.label,str(row.multiplier).trim_suffix(".0")])
	return "" if parts.is_empty() else heading+"："+" / ".join(parts)
