extends SceneTree
const Strip=preload("res://scripts/combat_status_strip.gd")
const Presenter=preload("res://core/combat_status_presenter.gd")
class CountingPresenter extends "res://core/combat_status_presenter.gd":
 var calls:int=0
 func present(unit:Dictionary,tick:int,definition:Dictionary,preparation:bool=false)->Dictionary:
  calls+=1;return super.present(unit,tick,definition,preparation)
var checks:int=0
var failures:int=0
func ck(value:bool,message:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func parity(strip,unit:Dictionary,tick:int,definition:Dictionary,preparation:bool=false)->void:
 var before=unit.duplicate(true);var defs=definition.duplicate(true)
 strip.update_unit(unit,tick,definition,preparation)
 ck(strip.status==Presenter.new().present(unit,tick,definition,preparation),"cached output matches fresh presenter")
 ck(unit==before and definition==defs,"inputs not mutated")
func run():
 var sim=load("res://core/character_sim.gd").new()
 var strip=Strip.new();strip.presenter=CountingPresenter.new();root.add_child(strip)
 var unit:Dictionary=sim.preview_unit("yuuka",2);var definition:Dictionary=sim.character_data("yuuka").duplicate(true)
 parity(strip,unit,40,definition)
 var calls:int=strip.presenter.calls;var rev:int=strip.revisions
 for i in 5:strip.update_unit(unit,40,definition,false)
 ck(strip.presenter.calls==calls,"unchanged authoritative input bypasses presenter")
 ck(strip.revisions==rev,"unchanged input preserves redraw revision")
 unit.cell=Vector2(1,2);unit.ammo=7;strip.update_unit(unit,40,definition,false)
 ck(strip.presenter.calls==calls,"unrelated movement/ammo bypass projection")
 for field in ["skill_ready","skill_cooldown_ticks","basic_ready","basic_activations","sub_ready","cover_ready","shield","shield_until","stun_until","taunt_until","charges","star","hp"]:
  unit[field]=int(unit.get(field,0))+57
  parity(strip,unit,40,definition)
 unit.buffs={"first":{"stat":"AttackPower","fraction":0.25,"until":90,"condition":""}}
 parity(strip,unit,40,definition)
 unit.buffs.first.fraction=-0.4;parity(strip,unit,40,definition)
 unit.buffs.first.condition="while_stationary";parity(strip,unit,40,definition)
 unit.buffs.first.until=39;parity(strip,unit,40,definition)
 unit.buffs.erase("first");parity(strip,unit,40,definition)
 for kind in ["periodic","hp_below_threshold","ammo_empty","ally_hp_below_threshold"]:
  definition.basic.trigger={"kind":kind,"intervalSeconds":15.0,"thresholdHpRatio":0.5,"activationLimitPerBattle":2,"internalCooldownSeconds":20.0}
  parity(strip,unit,40,definition)
 definition.basic.trigger={"kind":"periodic","intervalSeconds":15.0};unit.basic_ready=100
 parity(strip,unit,40,definition)
 definition.basic.trigger.intervalSeconds=27.0;parity(strip,unit,40,definition)
 definition.basic.trigger={"kind":"hp_below_threshold","thresholdHpRatio":0.5,"activationLimitPerBattle":1};unit.basic_ready=0;unit.basic_activations=0
 parity(strip,unit,40,definition)
 definition.basic.trigger.thresholdHpRatio=0.25;parity(strip,unit,40,definition)
 unit.basic_activations=1;parity(strip,unit,40,definition)
 definition.basic.trigger.activationLimitPerBattle=2;parity(strip,unit,40,definition)
 for kind in ["periodic","take_cover","while_stationary","while_reloading","on_ex_cast"]:
  definition.sub.trigger={"kind":kind,"intervalSeconds":17.0,"internalCooldownSeconds":19.0}
  parity(strip,unit,40,definition)
 definition.sub.trigger.internalCooldownSeconds=35.0;parity(strip,unit,40,definition)
 for tick in [41,42,40,0]:parity(strip,unit,tick,definition)
 parity(strip,unit,0,definition,true);parity(strip,unit,0,definition,false)
 unit.hp=0;parity(strip,unit,0,definition);unit.hp=30;parity(strip,unit,0,definition)
 unit.charges=1.25;parity(strip,unit,0,definition)
 unit.charges=1.75;parity(strip,unit,0,definition)
 # String conversion rounds near integer boundaries; gate/hint also read int.
 unit.charges=1.0-pow(2.0,-52);parity(strip,unit,0,definition)
 unit.charges=1.0;parity(strip,unit,0,definition)
 unit.charges=2.0-pow(2.0,-51);parity(strip,unit,0,definition)
 unit.charges=2.0;parity(strip,unit,0,definition)
 # Switching actors/definitions through a reused strip must not keep stale data.
 for character in ["shiroko","hoshino","hina","aru","yuuka","aris","serika","haruna","iori","mutsuki","nonomi","tsubaki","koharu"]:
  var u=sim.preview_unit(character,2);var d=sim.character_data(character)
  parity(strip,u,15,d);var count:int=strip.presenter.calls;strip.update_unit(u,15,d,false)
  ck(strip.presenter.calls==count,"reused strip caches "+character)
 strip.free();print("COMBAT_STATUS_CACHE ",checks," checks; ",failures," failures");quit(1 if failures else 0)
