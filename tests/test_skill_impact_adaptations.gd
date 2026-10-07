extends SceneTree
## Actual source prefabs/player; the fixture only supplies movable character anchors.
const Glue=preload("res://scripts/native_combat_vfx.gd")
const Source=preload("res://vfx/native_source.gd")
var checks:=0
var failures:=0
class View extends Node3D:
 var _model:Node3D
 func _init()->void:
  _model=Node3D.new();_model.name="ImportedCharacter";_model.scale=Vector3.ONE*1.3;add_child(_model)
  var ex:=Node3D.new();ex.name="Ex_Root";_model.add_child(ex)
  var dm:=Node3D.new();dm.name="FX_Local_DM";ex.add_child(dm)
  var socket:=Node3D.new();socket.name="fire_01";socket.position=Vector3(0,0.5,0.4);_model.add_child(socket)
 func hit_position()->Vector3:return global_position+Vector3.UP*0.7
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func effects(glue:Node3D,prefab:String)->Array:
 var result:Array=[]
 for effect in glue._player.get("_effects"):
  if str(effect.prefab)==prefab:result.append(effect)
 return result
func point(effect:Dictionary)->Vector3:return effect.resolver.call({}, {}, 99.0).origin
func damage(actor:int,target:int,ability:String,component:String,tick:int,cast_tick:int,id:String)->Dictionary:
 return {"type":"damage","actor_id":actor,"target_id":target,"ability":ability,"component":component,"tick":tick,"cast_start_tick":cast_tick,"cast_target_cell":Vector2(4,6),"target_cell":Vector2(19,21),"hit_index":0,"generation":8,"event_id":id,"amount":9}
func run()->void:
 var views:Dictionary={};var units:Array=[];var profiles:Dictionary={}
 var characters=["shiroko","aru","aris","yuuka","hoshino"]
 for i in range(characters.size()):
  var v:=View.new();root.add_child(v);v.position=Vector3(i*2,0,0);views[i+1]=v
  units.append({"id":i+1,"character_id":characters[i]})
  profiles[characters[i]]={"model_scale":1.3,"muzzle_anchor":"fire_01","anchors":[{"name":"fire_01","path":"fire_01"}]}
 var glue:=Glue.new();root.add_child(glue);glue.configure(profiles);glue.begin_roster(views,units,8)
 var original_source:=FileAccess.get_file_as_string("res://data/effects/battle-events-compact.json")
 var original_weapons:=FileAccess.get_file_as_string("res://data/effects/shared-weapons/visual-templates.json")
 # Removing damage-event support, firing from the preview, or deduping per victim fails this block.
 glue.consume({"type":"basic","ability":"basic","actor_id":1,"target_id":4,"tick":0,"cast_start_tick":0,"target_cell":Vector2(4,6),"generation":8,"event_id":"cast"},units)
 glue.update_time(1.5)
 ck(effects(glue,"FX_Common_Hit_Explosion_2M_World").is_empty(),"muted preview never plays before authoritative damage")
 var hit:=damage(1,4,"basic","",40,0,"shiroko-a");var unchanged:=hit.duplicate(true)
 glue.consume(hit,units);glue.consume(damage(1,5,"basic","",40,0,"shiroko-b"),units)
 glue.update_time(1.99)
 ck(effects(glue,"FX_Common_Hit_Explosion_2M_World").is_empty(),"queued future contact cannot appear early")
 glue.update_time(2.0)
 var explosions:=effects(glue,"FX_Common_Hit_Explosion_2M_World")
 ck(explosions.size()==1,"AoE produces one source explosion per cast hit component")
 if explosions.size()==1:
  ck(point(explosions[0]).is_equal_approx(Vector3(4,0,6)),"AoE uses recorded cast ground point rather than victim or current target_cell")
  ck(is_equal_approx(explosions[0].start,2.0),"effect begins exactly at damage timestamp")
  ck(not explosions[0].layers.is_empty(),"selected source explosion has implemented layers")
 ck(hit==unchanged,"presentation does not mutate damage event")
 var duplicate:=hit.duplicate(true);duplicate.event_id="redelivery";duplicate.tick=41
 glue.consume(duplicate,units);glue.update_time(2.05)
 ck(effects(glue,"FX_Common_Hit_Explosion_2M_World").size()==1,"cast hit component dedup survives different event IDs and redelivery ticks")
 # Wrong direct anchor or following the victim after contact fails this block.
 glue.consume(damage(2,4,"basic","direct",42,1,"aru-basic"),units);glue.update_time(2.1)
 var direct:=effects(glue,"FX_Public_Aru_Hit_Start_1")
 ck(direct.size()==1,"Aru basic direct damage gets its authored Hit_Start asset")
 if direct.size()==1:ck(point(direct[0]).is_equal_approx(Vector3(6,0.7,0)),"direct hit freezes current victim body point")
 views[4].position=Vector3(16,0,0);glue.update_time(2.15)
 if direct.size()==1:ck(point(direct[0]).is_equal_approx(Vector3(6,0.7,0)),"direct effect stays at contact after victim moves")
 glue.consume(damage(2,4,"ex","direct",44,2,"aru-ex-direct"),units)
 glue.consume(damage(2,4,"ex","explosion",44,2,"aru-ex-aoe-a"),units)
 glue.consume(damage(2,5,"ex","explosion",44,2,"aru-ex-aoe-b"),units);glue.update_time(2.2)
 ck(effects(glue,"FX_Aru_Original_Ex01_Hit_Start").size()==1,"EX direct remains distinct from its explosion component")
 var aru_aoe:=effects(glue,"FX_Aru_Original_Ex01_Hit_Explosion")
 ck(aru_aoe.size()==1,"Aru EX explosion is deduplicated across victims")
 if aru_aoe.size()==1:ck(point(aru_aoe[0]).is_equal_approx(Vector3(4,0,6)),"Aru EX explosion uses cast target ground point")
 glue.consume(damage(3,4,"ex","",45,3,"aris-a"),units);glue.consume(damage(3,5,"ex","",45,3,"aris-b"),units);glue.update_time(2.25)
 ck(effects(glue,"FX_Aris_Original_Ex01_Motion_Hit_Start").size()==2,"Aris line damage has one direct impact per actual victim")
 var before:int=int(glue.diagnostics().get("adapted_skill_hits_spawned",0))
 for variant in ["miss","echo","stale","unknown"]:
  var ignored:=damage(1,4,"basic","",46,9,variant)
  if variant=="miss":ignored.type="miss"
  if variant=="echo":ignored.component="echo"
  if variant=="stale":ignored.generation=7
  if variant=="unknown":ignored.component="unknown"
  glue.consume(ignored,units)
 glue.update_time(2.3)
 ck(int(glue.diagnostics().get("adapted_skill_hits_spawned",0))==before,"miss echo stale and unselected component cannot add impacts")
 ck(glue.diagnostics().get("adaptation_classification","")=="AUTOCHESS VISUAL ADAPTATIONS","diagnostics label adaptation boundary")
 ck(glue.diagnostics().get("native_runtime_binding_verified",true)==false,"diagnostics do not claim recovered runtime selectors")
 var snap:Dictionary=glue.visual_snapshot();glue.update_time(2.3);ck(snap==glue.visual_snapshot(),"pause leaves impact particles unchanged")
 # Missing recorded area target must fail closed instead of using victim coordinates.
 var missing:=damage(1,4,"basic","",47,999,"missing-point");missing.erase("cast_target_cell")
 glue.consume(missing,units);glue.update_time(2.35)
 ck(int(glue.diagnostics().get("adapted_skill_hits_spawned",0))==before,"missing recorded AoE center cannot invent a victim-center fallback")
 ck(glue.diagnostics().issues.any(func(x):return x.code=="missing_adapted_cast_target"),"missing AoE center is reported")
 # RF is only an explicit Aru SR visual fallback; exact source null is immutable.
 glue.consume(damage(2,4,"normal","normal",48,4,"aru-normal"),units);glue.update_time(2.4)
 ck(effects(glue,"FX_Muzzle_RF").size()==1,"Aru SR plays inspected same-game RF visual fallback")
 ck(int(glue.diagnostics().get("adapted_muzzles_spawned",0))==1,"RF fallback gets separate adaptation diagnostic count")
 ck(int(glue.diagnostics().get("exact_muzzles_spawned",-1))==0,"fallback is never counted as exact source mapping")
 ck(Source.read_json("res://data/effects/shared-weapons/visual-templates.json").weaponFamilies.SR.muzzlePrefab==null,"source SR exact mapping remains null")
 ck(FileAccess.get_file_as_string("res://data/effects/battle-events-compact.json")==original_source,"source timeline including muted records stays byte-identical")
 ck(FileAccess.get_file_as_string("res://data/effects/shared-weapons/visual-templates.json")==original_weapons,"source weapon mapping stays byte-identical")
 glue.update_time(30)
 ck(glue.diagnostics().active_handles==0,"source lifetime tails release through inherited pool")
 glue.reset(9);ck(glue.diagnostics().active_handles==0 and glue.diagnostics().queued_events==0,"reset cancels impacts and queued events")
 glue.free()
 for v in views.values():v.free()
 print("SKILL_IMPACT_ADAPTATIONS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
