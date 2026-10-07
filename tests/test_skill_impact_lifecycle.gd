extends SceneTree
const Glue=preload("res://scripts/native_combat_vfx.gd")
const Fixture=preload("res://tests/test_skill_impact_adaptations.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func matching(glue:Node3D,prefab:String)->Array:
 var matches:Array=[]
 for e in glue._player.get("_effects"):
  if str(e.prefab)==prefab:matches.append(e)
 return matches
func run()->void:
 var actor:=Fixture.View.new();root.add_child(actor)
 var victim:=Fixture.View.new();root.add_child(victim);victim.position=Vector3(6,0,0)
 var profiles={"aru":{"model_scale":1.3,"muzzle_anchor":"fire_01","anchors":[{"name":"fire_01","path":"fire_01"}]},"shiroko":{"model_scale":1.3}}
 var units=[{"id":1,"character_id":"aru"},{"id":2,"character_id":"shiroko"}]
 var glue:=Glue.new();root.add_child(glue);glue.configure(profiles);glue.begin_roster({1:actor,2:victim},units,5)
 ck(int(glue.diagnostics().get("adaptations_warmed",0))==5,"all roster impact assets and optional RF fallback warm before battle")
 ck(glue.diagnostics().active_handles==0 and glue.diagnostics().native.active_effects==0,"warmup leaves no playing source effects")
 ck(glue.diagnostics().native.pooled_nodes>0,"warmup prepares bounded render-node pool")
 # Late render frames must sample damage time, never today's body point.
 victim.position=Vector3(14,0,0)
 var direct={"type":"damage","ability":"basic","component":"direct","actor_id":1,"target_id":2,"tick":30,"cast_start_tick":0,"cast_target_cell":Vector2(6,0),"hit_index":0,"generation":5,"event_id":"late"}
 glue.consume(direct,units);glue.update_time(2.0)
 var hits:=matching(glue,"FX_Public_Aru_Hit_Start_1")
 ck(hits.size()==1,"late-frame authoritative contact still starts a source effect")
 if hits.size()==1:
  ck(hits[0].resolver.call({}, {}, 2.0).origin.is_equal_approx(Vector3(12,0.7,0)),"late-frame direct uses interpolated body at contact time")
  ck(is_equal_approx(hits[0].start,1.5),"late-frame effect retains authoritative start and age")
 # Older events may use a retained cast record, but must never use current victim coordinates.
 glue.consume({"type":"skill","ability":"ex","actor_id":1,"target_id":2,"tick":41,"target_cell":Vector2(-2,7),"generation":5,"event_id":"old-cast"},units)
 glue.update_time(2.05)
 glue.consume({"type":"damage","ability":"ex","component":"explosion","actor_id":1,"target_id":2,"tick":42,"target_cell":Vector2(100,100),"hit_index":0,"generation":5,"event_id":"old-hit"},units);glue.update_time(2.1)
 var area:=matching(glue,"FX_Aru_Original_Ex01_Hit_Explosion")
 ck(area.size()==1,"older fixtures can use recorded cast context")
 if area.size()==1:ck(area[0].resolver.call({}, {}, 9.0).origin.is_equal_approx(Vector3(-2,0,7)),"legacy fallback preserves recorded target point")
 ck(glue.diagnostics().issues.any(func(x):return x.code=="legacy_cast_context_adaptation"),"older fixture fallback is explicitly diagnosed")
 var unsupported={"type":"damage","ability":"basic","component":"explosion","actor_id":1,"target_id":2,"tick":43,"cast_start_tick":41,"cast_target_cell":Vector2(0,0),"generation":5,"event_id":"unsupported-basic"}
 var before:int=int(glue.diagnostics().get("adapted_skill_hits_spawned",0))
 glue.consume(unsupported,units);glue.update_time(2.15)
 ck(int(glue.diagnostics().get("adapted_skill_hits_spawned",0))==before,"unsupported basic explosion cannot silently reuse EX asset")
 ck(glue.diagnostics().issues.any(func(x):return x.code=="unsupported_skill_impact"),"unsupported selected character component is reported")
 # Different cast and hit identities are independent even when their contacts coincide.
 for cast_tick in [1,2]:
  for hit_index in [0,1]:
   var e:Dictionary=direct.duplicate();e.tick=44;e.cast_start_tick=cast_tick;e.hit_index=hit_index;e.event_id="overlap-%d-%d"%[cast_tick,hit_index]
   glue.consume(e,units)
 glue.update_time(2.2)
 ck(int(glue.diagnostics().get("adapted_skill_hits_spawned",0))==before+4,"dedup preserves distinct casts and hit indices")
 # A dead victim retains its last body anchor; an already-landed source effect gets its full tail.
 glue.consume({"type":"death","actor_id":2,"tick":44,"generation":5,"event_id":"dead"},units);glue.update_time(2.25)
 ck(int(glue.diagnostics().get("adapted_skill_hits_spawned",0))==before+4,"death creates no autonomous impact")
 ck(not matching(glue,"FX_Public_Aru_Hit_Start_1").is_empty(),"death notification does not erase landed contact tails")
 glue.max_live_handles=1
 var capped:Dictionary=direct.duplicate();capped.tick=46;capped.cast_start_tick=4;capped.event_id="cap"
 glue.consume(capped,units);glue.update_time(2.3)
 ck(glue.diagnostics().active_handles<=1 and glue.diagnostics().budget_releases>0,"adapted impacts share inherited handle cap")
 var future:Dictionary=direct.duplicate();future.tick=1000;future.event_id="future"
 glue.consume(future,units);glue.reset(6);glue.update_time(60)
 ck(glue.diagnostics().active_handles==0 and glue.diagnostics().queued_events==0,"generation reset cancels pending adaptation and all source tails")
 # Real source container has no active emitter. Warming/spawning must not count it as implemented.
 glue._adaptations.skills["shiroko:basic:"].template="res://data/effects/shiroko/visual-templates.json#FX_Common_DroneMissile"
 glue.begin_roster({1:actor,2:victim},units,7)
 ck(glue.diagnostics().issues.any(func(x):return x.code=="unsupported_empty_adaptation"),"empty recovered source prefab is diagnosed during warmup")
 glue.consume({"type":"damage","ability":"basic","component":"","actor_id":2,"target_id":1,"tick":1,"cast_start_tick":0,"cast_target_cell":Vector2(1,1),"generation":7,"event_id":"empty"},units);glue.update_time(0.05)
 ck(int(glue.diagnostics().get("adapted_skill_hits_spawned",0))==0,"empty source prefab never increments implemented-hit count")
 ck(matching(glue,"FX_Common_DroneMissile").is_empty(),"unsupported empty source handle is released")
 glue.free();actor.free();victim.free()
 print("SKILL_IMPACT_LIFECYCLE ",checks," checks; ",failures," failures");quit(1 if failures else 0)
