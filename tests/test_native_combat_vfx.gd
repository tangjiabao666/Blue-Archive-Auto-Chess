extends SceneTree
var checks:=0
var failures:=0
class MockView extends Node3D:
 var _model:Node3D
 var socket:Node3D
 func _init()->void:
  _model=Node3D.new();_model.name="ImportedCharacter";add_child(_model);_model.scale=Vector3.ONE*1.3;_model.rotation.y=PI
  var ex:=Node3D.new();ex.name="Ex_Root";_model.add_child(ex)
  var dm:=Node3D.new();dm.name="FX_Local_DM";ex.add_child(dm)
  socket=Node3D.new();socket.name="fire_01";socket.position=Vector3(0,0.5,0.4);_model.add_child(socket)
  var calculator:=Node3D.new();calculator.name="bone_Calculator";calculator.position=Vector3(0,0.4,0);_model.add_child(calculator)
 func muzzle_transform()->Transform3D:return socket.global_transform
 func hit_position()->Vector3:return global_position+Vector3.UP*0.7
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var script=load("res://scripts/native_combat_vfx.gd")
 ck(script!=null,"native glue exists")
 if script==null:quit(1);return
 var actor:=MockView.new();root.add_child(actor)
 var target:=MockView.new();target.position=Vector3(2,0,0);root.add_child(target)
 var target2:=MockView.new();target2.position=Vector3(3,0,0);root.add_child(target2)
 var profiles={"shiroko":{"model_scale":1.3,"muzzle_anchor":"fire_01","anchors":[{"name":"fire_01","path":"fire_01"}]},"yuuka":{"model_scale":1.3},"aru":{"model_scale":1.3,"muzzle_anchor":"fire_01","anchors":[{"name":"fire_01","path":"fire_01"}]}}
 var units=[{"id":1,"character_id":"shiroko"},{"id":2,"character_id":"yuuka"},{"id":3,"character_id":"aru"}]
 var glue=script.new();root.add_child(glue);glue.configure(profiles);glue.begin_roster({1:actor,2:target,3:target2},units,8)
 actor.position.x=10.0
 glue.update_time(1.0)
 var historical=glue._sample_anchor(1,"@muzzle",0.5)
 ck(historical!=null and is_equal_approx((historical as Transform3D).origin.x,5.0),"world-space birth anchor interpolates recorded history")
 var at:int=100
 var hit={"type":"damage","ability":"normal","actor_id":1,"target_id":2,"tick":at,"hit_index":0,"generation":8,"event_id":"a"}
 glue.update_time(4.9);glue.consume(hit,units)
 var duplicate:Dictionary=hit.duplicate();duplicate.event_id="b";duplicate.target_id=3;glue.consume(duplicate,units)
 var echo:Dictionary=hit.duplicate();echo.event_id="c";echo.component="echo";glue.consume(echo,units)
 glue.consume(hit,units);glue.update_time(5.0)
 var d:Dictionary=glue.diagnostics()
 ck(d.muzzles_spawned==1,"fan/multidamage yields one muzzle per actor tick hit")
 ck(d.hits_spawned==2,"each primary victim gets one native common hit")
 ck(d.echoes_skipped==1,"echo does not duplicate projectile effects")
 var fixed_origin:Vector3=Vector3.ZERO
 for effect in glue._player.get("_effects"):
  if str(effect.prefab)=="FX_Common_Hit_AR_Normal":
   fixed_origin=effect.resolver.call({}, {}, 10.0).origin;break
 target.position.x=20.0
 ck(is_equal_approx(fixed_origin.x,2.0),"native hit contact anchor is frozen when victim moves")
 var root_transform:Transform3D=glue.resolve_live_anchor(1,"Shiroko_Original/Ex_Root")
 var expected:Transform3D=actor._model.global_transform*Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)
 ck(root_transform.is_equal_approx(expected),"GLB reflectX to VFX reflectZ uses right Ypi basis with model scale")
 glue.consume({"type":"skill","ability":"ex","actor_id":2,"tick":102,"generation":8,"event_id":"ex","recovery_ticks":10},units);glue.update_time(5.1)
 ck(glue.diagnostics().timelines_spawned==1,"EX starts native timeline")
 ck(glue.handle_deadlines().any(func(x):return is_equal_approx(float(x.end),5.1+2.3333333333333335)),"native EX duration distinct from 0.5 second sim cast")
 glue.consume({"type":"damage","ability":"normal","actor_id":3,"target_id":2,"tick":103,"hit_index":0,"generation":8,"event_id":"sr"},units);glue.update_time(5.15)
 ck(glue.diagnostics().muzzles_spawned==2 and glue.diagnostics().adapted_muzzles_spawned==1 and glue.diagnostics().exact_muzzles_spawned==1,"explicit Aru SR fallback remains distinct from exact weapon mapping")
 ck(glue._weapon_families.SR.muzzlePrefab==null,"SR source exact mapping remains null")
 glue.consume({"type":"basic","ability":"basic","actor_id":2,"tick":104,"generation":7,"event_id":"old"},units);glue.update_time(5.2)
 ck(glue.diagnostics().timelines_spawned==1,"stale generation ignored")
 var snap:Dictionary=glue.visual_snapshot();glue.update_time(5.2);ck(snap==glue.visual_snapshot(),"same gameclock pause unchanged")
 glue.update_time(30);ck(glue.diagnostics().active_handles==0,"all source handles released after exact windows")
 glue.reset(9);ck(glue.diagnostics().active_handles==0 and glue.diagnostics().queued_events==0,"reset clears glue state")
 glue.begin_roster({1:actor,2:target,3:target2},units,10)
 glue.max_live_handles=1
 glue.consume({"type":"damage","ability":"normal","actor_id":1,"target_id":2,"tick":0,"hit_index":0,"generation":10,"event_id":"cap"},units);glue.update_time(0)
 ck(glue.diagnostics().active_handles<=1 and glue.diagnostics().budget_releases>0,"live handle budget enforced")
 glue.max_queued_events=1
 for i in range(3):glue.consume({"type":"damage","ability":"normal","actor_id":1,"target_id":2,"tick":1000+i,"hit_index":i,"generation":10,"event_id":"future-"+str(i)},units)
 ck(glue.diagnostics().queued_events<=1,"future event queue bounded")
 glue.reset(11)
 ck(glue.diagnostics().queued_events==0 and glue.diagnostics().active_handles==0,"reset cancels future queued events and live visuals")
 glue.max_history_samples=-1;glue.max_live_handles=-1
 glue.update_time(60)
 ck(glue.diagnostics().active_handles==0,"invalid negative caps do not cause unbounded loops")
 glue.free();actor.free();target.free();target2.free()
 print("COMBAT_VFX_TESTS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
