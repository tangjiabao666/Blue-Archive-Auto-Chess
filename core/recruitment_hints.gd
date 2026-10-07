extends RefCounted
## Read-only shop presentation. Never rolls offers or reserves/spends gold.
static func copy_counts(player:Dictionary,character_id:String)->Dictionary:
	var counts:Dictionary={"one_star":0,"two_star":0}
	var located:Array=player.get("deployed",[])+player.get("bench",[])
	for unit in player.get("units",[]):
		if unit.id not in located or unit.character_id!=character_id:continue
		if unit.star==1:counts.one_star+=1
		elif unit.star==2:counts.two_star+=1
	return counts

static func card_hint(player:Dictionary,character_id:String,display_name:String)->Dictionary:
	var counts:Dictionary=copy_counts(player,character_id)
	var label:String="仅二星" if counts.one_star==0 and counts.two_star>0 else "一星 %d/3"%counts.one_star
	var tooltip:String="%s：一星 %d/3（场上 + 备战席）\n已拥有二星：%d\n三个相同一星自动合成为一个二星；二星不计入一星进度。"%[display_name,counts.one_star,counts.two_star]
	return {"label":label,"tooltip":tooltip}

static func refresh_hint(player:Dictionary,catalog:Array,config:Dictionary,selected_unit_id:String)->String:
	var refresh_cost:int=int(config.refresh_cost)
	var generic:String="刷新 %d 金币，随机更新招募角色。\n不保证出现任何指定角色。选择已拥有角色可查看一次刷新 + 再购买 1 张的金币预算。"%refresh_cost
	var located:Array=player.get("deployed",[])+player.get("bench",[])
	if selected_unit_id.is_empty() or selected_unit_id not in located:return generic
	var character_id:String=""
	for unit in player.get("units",[]):
		if unit.id==selected_unit_id:character_id=unit.character_id;break
	for character in catalog:
		if character.id!=character_id:continue
		var display_name:String=character.get("name",character_id)
		var cost:int=int(character.cost)
		return card_hint(player,character_id,display_name).tooltip+"\n刷新 %d + 再购买 1 张 %d = %d 金币。\n这只是一次刷新及购买一张的金币预算；刷新可能没有%s，不保证合成。"%[refresh_cost,cost,refresh_cost+cost,display_name]
	return generic
