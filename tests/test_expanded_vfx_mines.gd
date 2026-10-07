extends SceneTree
const Glue=preload("res://scripts/native_combat_vfx.gd")
const Fixture=preload("res://tests/test_skill_impact_adaptations.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func matches(glue:Node3D)->Array:
 var result:Array=[]
 for e in glue._player.get("_effects"):
  if e.prefab=="FX_Mutsuki_Explosion":result.append(e)
 return result
func hit(mine_id:int,target_id:int,origin:Vector2,id:String)->Dictionary:
 return {"type":"damage","ability":"basic","component":"mine","actor_id":1,"target_id":target_id,"origin":origin,"target_cell":Vector2(20,20),"cast_target_cell":Vector2(30,30),"cast_start_tick":0,"tick":20,"hit_index":0,"mine_id":mine_id,"generation":4,"event_id":id}
func run()->void:
 var actor:=Fixture.View.new();root.add_child(actor)
 var target:=Fixture.View.new();root.add_child(target);target.position=Vector3(20,0,20)
 var units=[{"id":1,"character_id":"mutsuki"},{"id":2,"character_id":"yuuka"}]
 var glue:=Glue.new();root.add_child(glue);glue.configure({"mutsuki":{"model_scale":1.3},"yuuka":{"model_scale":1.3}});glue.begin_roster({1:actor,2:target},units,4)
 for event_type in ["mine_placed","mine_triggered","mine_expired","mine_removed"]:
  glue.consume({"type":event_type,"actor_id":1,"cell":Vector2(2,3),"tick":20,"mine_id":0,"generation":4},units)
 glue.update_time(0.5);ck(matches(glue).is_empty(),"mine lifecycle notifications do not invent pre-contact explosions")
 for mine_id in range(3):
  var origin:=Vector2(2,3) if mine_id<2 else Vector2(-2,3)
  glue.consume(hit(mine_id,2,origin,"mine-"+str(mine_id)),units)
  glue.consume(hit(mine_id,9,origin,"victim-"+str(mine_id)),units)
 glue.update_time(0.99);ck(matches(glue).is_empty(),"mine explosion waits for authoritative damage timestamp")
 glue.update_time(1.0)
 var effects:=matches(glue)
 ck(effects.size()==3,"three mine IDs from one cast each spawn once, even two overlapping mines")
 var centers:Array=[]
 for e in effects:centers.append(e.resolver.call({}, {}, 9.0).origin)
 ck(centers.count(Vector3(2,0,3))==2 and centers.count(Vector3(-2,0,3))==1,"mine ground effects use actual origin instead of victim or original cast target")
 var duplicate:=hit(0,2,Vector2(2,3),"later-duplicate");duplicate.tick=21
 glue.consume(duplicate,units);glue.update_time(1.05)
 ck(matches(glue).size()==3,"mine identity suppresses repeated damage delivery at another tick")
 var late:=hit(2,2,Vector2(-2,3),"old-generation");late.generation=3
 glue.consume(late,units);glue.update_time(1.1);ck(matches(glue).size()==3,"stale generation cannot add a mine impact")
 var missing_origin:=hit(99,2,Vector2(8,8),"missing-origin");missing_origin.tick=22;missing_origin.erase("origin")
 glue.consume(missing_origin,units);glue.update_time(1.1)
 ck(matches(glue).size()==3,"missing mine origin never falls back to the old cast aim")
 ck(glue.diagnostics().issues.any(func(x):return x.code=="missing_adapted_mine_origin"),"missing mine origin has a precise diagnostic")
 var snap:Dictionary=glue.visual_snapshot();glue.update_time(1.1);ck(snap==glue.visual_snapshot(),"paused mine impacts use the same game clock")
 glue.max_live_handles=1
 var next:=hit(3,2,Vector2(4,3),"cap");next.tick=23
 glue.consume(next,units);glue.update_time(1.15)
 ck(glue.diagnostics().active_handles<=1 and glue.diagnostics().budget_releases>0,"mine impacts share existing bounded handles")
 var future:=hit(4,2,Vector2(4,3),"future");future.tick=100
 glue.consume(future,units);glue.reset(5);glue.update_time(6.0)
 ck(glue.diagnostics().queued_events==0 and glue.diagnostics().active_handles==0,"generation reset cancels future mine impacts")
 glue.free();actor.free();target.free()
 print("EXPANDED_VFX_MINES ",checks," checks; ",failures," failures");quit(1 if failures else 0)
