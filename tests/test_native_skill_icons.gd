extends SceneTree
class MissingIcons extends "res://scripts/native_skill_icons.gd":
 func texture(_key:String)->Texture2D:return null
var failures:=0
var checks:=0
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func _initialize():call_deferred("run")
func run():
 ck(ResourceLoader.exists("res://scripts/native_skill_icons.gd"),"source icon resolver exists")
 if failures:quit(1);return
 var icons=load("res://scripts/native_skill_icons.gd").new()
 for character in ["shiroko","hoshino","hina","aru","yuuka","aris","serika","iori","tsubaki","nonomi","mutsuki","haruna","koharu"]:
  for slot in ["ex","basic","sub"]:
   var key:String=icons.skill_key(character,slot)
   ck(not key.is_empty(),character+" "+slot+" mapped")
   ck(icons.texture(key)!=null,"mapped source texture loads")
   ck(icons.region(key).has_area(),"nonempty alpha bounds")
 ck(icons.skill_key("unknown","ex")=="","unknown character fallback")
 ck(icons.skill_key("shiroko","unknown")=="","unknown slot fallback")
 ck(icons.effect_key({"id":"shield"},{},0)=="buff/Buff_Shield","shield mapping")
 ck(icons.effect_key({"id":"charge"},{},1)=="buff/Special_EnergyBatteryHalf","charge one")
 ck(icons.effect_key({"id":"charge"},{},2)=="buff/Special_EnergyBatteryFull","charge two")
 ck(icons.effect_key({"id":"test"},{"test":{"stat":"AttackPower","fraction":0.2}},0)=="buff/Buff_ATK","attack buff")
 ck(icons.effect_key({"id":"test"},{"test":{"stat":"AttackPower","fraction":-0.2}},0)=="","no guessed debuff icon")
 ck(icons.effect_key({"id":"overflow"},{},0)=="","overflow retains count")
 var strip=load("res://scripts/combat_status_strip.gd").new();root.add_child(strip)
 var sim=load("res://core/character_sim.gd").new();var unit:Dictionary=sim.preview_unit("shiroko",2);var def:Dictionary=sim.character_data("shiroko")
 strip.update_unit(unit,0,def,true)
 var old_status:Dictionary=strip.status.duplicate(true);var old_revision:int=strip.revisions
 unit.character_id="yuuka"
 strip.update_unit(unit,0,def,true)
 ck(strip.status==old_status,"identity only does not alter authoritative status")
 ck(strip.revisions==old_revision+1,"identity-only change redraws glyph")
 ck(strip.skill_icon_keys[0]=="skill/COMMON_SKILLICON_SHIELD","reused strip updates identity")
 old_revision=strip.revisions;strip.update_unit(unit,0,def,true)
 ck(strip.revisions==old_revision,"unchanged identity avoids redraw")
 unit.buffs={"buff":{"stat":"AttackPower","fraction":0.2,"until":100}}
 strip.update_unit(unit,0,def,false)
 ck(strip.effect_icon_keys==["buff/Buff_ATK"],"same-tick attack buff icon")
 unit.buffs.buff.stat="DefensePower"
 strip.update_unit(unit,0,def,false)
 ck(strip.effect_icon_keys==["buff/Buff_DEF"],"same-tick buff semantic mutation refreshes icon")
 unit.buffs.buff.fraction=-0.2
 strip.update_unit(unit,0,def,false)
 ck(strip.effect_icon_keys==[""],"negative effect falls back to authoritative text")
 ck(strip._has_icon("skill/COMMON_SKILLICON_SHIELD"),"valid icon renders")
 strip.icons=MissingIcons.new()
 ck(not strip._has_icon("skill/COMMON_SKILLICON_SHIELD"),"unavailable mapped texture retains textual path")
 strip.free();print("NATIVE_SKILL_ICONS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
