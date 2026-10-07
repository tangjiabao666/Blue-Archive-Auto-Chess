extends SceneTree
const Glue=preload("res://scripts/native_combat_vfx.gd")
const Source=preload("res://vfx/native_source.gd")
const Fixture=preload("res://tests/test_skill_impact_adaptations.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func effects(glue:Node3D,prefab:String)->Array:
 var result:Array=[]
 for e in glue._player.get("_effects"):
  if e.prefab==prefab:result.append(e)
 return result
func contact(kind:String,ability:String,component:String,target:int,tick:int,cast_tick:int,id:String)->Dictionary:
 return {"type":kind,"ability":ability,"component":component,"actor_id":1,"target_id":target,"tick":tick,"cast_start_tick":cast_tick,"cast_target_cell":Vector2(4,7),"target_cell":Vector2(40,70),"hit_index":0,"hit_count":1,"generation":6,"event_id":id,"amount":12}
func run()->void:
 var profiles:Dictionary={};var views:Dictionary={};var units:Array=[]
 var chars=["koharu","iori","haruna","yuuka","hoshino","aru"]
 for i in range(chars.size()):
  var v:=Fixture.View.new();root.add_child(v);v.position=Vector3(i*2,0,0);views[i+1]=v
  units.append({"id":i+1,"character_id":chars[i]})
  profiles[chars[i]]={"model_scale":1.3,"muzzle_anchor":"fire_01","anchors":[{"name":"fire_01","path":"fire_01"}]}
 var glue:=Glue.new();root.add_child(glue);glue.configure(profiles)
 glue.begin_roster(views,units,6)
 var heal_name:="FX_Public_Healpack_Hit_Start";var ex_name:="FX_Koharu_Original_Ex01_Hit_Explosion"
 ck(glue._adaptations.skills.get("koharu:basic:",{}).get("eventTypes",[])==["heal"],"Koharu basic policy explicitly accepts heal only")
 ck(glue._adaptations.skills.get("koharu:ex:circle",{}).get("eventTypes",[])==["damage","heal"],"Koharu EX policy explicitly accepts both actual contact types")
 var heal:=contact("heal","basic","",4,20,0,"heal");var unchanged:=heal.duplicate(true)
 glue.consume(heal,units);glue.update_time(0.99);ck(effects(glue,heal_name).is_empty(),"heal effect cannot precede contact tick")
 glue.update_time(1.0)
 var hits:=effects(glue,heal_name)
 ck(hits.size()==1,"successful basic heal creates its source impact")
 if hits.size()==1:ck(hits[0].resolver.call({}, {}, 99.0).origin==Vector3(6,0.7,0),"healing impact uses victim body at actual contact")
 ck(heal==unchanged,"presentation preserves authoritative heal metadata")
 views[4].position=Vector3(18,0,0);glue.update_time(1.05)
 if hits.size()==1:ck(hits[0].resolver.call({}, {}, 99.0).origin==Vector3(6,0.7,0),"healing impact remains fixed after recipient moves")
 # Heal-first and damage-first delivery must each produce one explosion, never two.
 for cast_tick in [10,11]:
  var first:String="heal" if cast_tick==10 else "damage"
  var second:String="damage" if cast_tick==10 else "heal"
  glue.consume(contact(first,"ex","circle",4,22,cast_tick,"first-"+str(cast_tick)),units)
  glue.consume(contact(second,"ex","circle",5,22,cast_tick,"second-"+str(cast_tick)),units)
  glue.consume(contact("heal","ex","circle",3,22,cast_tick,"ally-"+str(cast_tick)),units)
 glue.update_time(1.1)
 var explosions:=effects(glue,ex_name)
 ck(explosions.size()==2,"mixed EX recipients dedup once per cast independent of delivery order")
 for e in explosions:ck(e.resolver.call({}, {}, 99.0).origin==Vector3(4,0,7),"shared EX damage/heal uses exact chosen ground center")
 var before:int=int(glue.diagnostics().get("adapted_skill_hits_spawned",0))+int(glue.diagnostics().get("adapted_skill_heals_spawned",0))
 for kind in ["heal_missed","miss","damage","heal"]:
  var rejected:=contact(kind,"basic","",4,23,12,"rejected-"+kind)
  if kind=="heal":rejected.generation=5
  glue.consume(rejected,units)
 var damage_only:=contact("heal","basic","direct",4,23,12,"damage-only-policy");damage_only.actor_id=6
 glue.consume(damage_only,units)
 glue.consume(contact("heal","ex","echo",4,23,12,"echo"),units);glue.update_time(1.15)
 ck(effects(glue,"FX_Public_Aru_Hit_Start_1").is_empty(),"existing damage-only policy without eventTypes denies healing by default")
 ck(int(glue.diagnostics().get("adapted_skill_hits_spawned",0))+int(glue.diagnostics().get("adapted_skill_heals_spawned",0))==before,"missed heals, wrong policy type, stale and echo events create no effect")
 ck(int(glue.diagnostics().get("adapted_skill_heals_spawned",0))==2,"diagnostics distinguish two heal-triggered source effects")
 var snap:Dictionary=glue.visual_snapshot();glue.update_time(1.15);ck(snap==glue.visual_snapshot(),"paused heal effects remain unchanged")
 glue.consume({"type":"death","actor_id":4,"tick":23,"generation":6},units);glue.update_time(1.2)
 ck(not effects(glue,heal_name).is_empty(),"death notification does not invent or erase already-landed healing tails")
 for actor in [1,2,3]:
  var normal:=contact("damage","normal","normal",4,25,20,"rf-"+str(actor));normal.actor_id=actor
  glue.consume(normal,units)
 glue.update_time(1.25)
 ck(effects(glue,"FX_Muzzle_RF").size()==3,"Koharu Iori and Haruna each get explicit source RF fallback")
 ck(glue.diagnostics().adapted_muzzles_spawned==3 and glue.diagnostics().exact_muzzles_spawned==0,"new SR fallbacks remain separately diagnosed")
 ck(glue._weapon_families.SR.muzzlePrefab==null,"exact SR source mapping remains null")
 glue.max_queued_events=1
 for i in range(3):glue.consume(contact("heal","basic","",4,100+i,80+i,"queued-"+str(i)),units)
 ck(glue.diagnostics().queued_events==1 and glue.diagnostics().queue_budget_drops==2,"heal contacts obey existing bounded queue")
 glue.reset(7);glue.update_time(10.0)
 ck(glue.diagnostics().queued_events==0 and glue.diagnostics().active_handles==0,"reset clears queued heals and all impact handles")
 glue.free()
 for v in views.values():v.free()
 print("EXPANDED_VFX_HEALS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
