extends SceneTree
const Props=preload("res://scripts/native_skill_props.gd")
var failures:=0
var checks:=0
class MockView extends Node3D:
 var _model:Node3D
 var is_dead:=false
 func _init()->void:
  _model=Node3D.new();_model.name="Shiroko_Original";add_child(_model)
  _model.scale=Vector3.ONE*1.3;_model.rotation.y=PI
  var ex:=Node3D.new();ex.name="Ex_Root";_model.add_child(ex)
func ck(ok:bool,message:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
 var view:=MockView.new();root.add_child(view)
 var props:=Props.new();root.add_child(props)
 var units=[{"id":1,"character_id":"shiroko"}]
 props.configure({"shiroko":{"model_scale":1.3}});props.begin_roster({1:view},units,5)
 ck(props.diagnostics().native_muzzle.pooled_nodes>0,"nested muzzle warmed before first EX")
 ck(int(props.diagnostics().get("cached_prop_materials",0))==2,"native body and rotor materials warmed before first EX")
 var event={"type":"skill","ability":"ex","actor_id":1,"tick":20,"generation":5,"event_id":"ex1"}
 props.consume(event,units);props.update_time(0.5)
 ck(props.diagnostics().active_props==0,"future event waits")
 props.update_time(1.0)
 ck(props.diagnostics().active_props==1,"source Shiroko drone spawns on native EX start")
 props.update_time(4.0)
 var snap:Dictionary=props.snapshot()
 ck(snap.has(1),"drone exposes actual imported frame pose")
 if snap.has(1):
  ck(absf(float(snap[1].native_time)-3.0)<0.00001,"native timeline clock uncompressed")
  ck(absf(float(snap[1].local_position[1])-2.17199993133545)<0.0001,"source takeoff pose at three seconds")
  ck(snap[1].mesh_count==2,"original body and alpha rotor meshes")
  ck(snap[1].body_shader.ends_with("native_weapon.gdshader"),"source body material uses verified native weapon shader")
  ck(snap[1].rotor_transparency==1,"source transparent rotor alpha preserved")
 ck(props.diagnostics().native_muzzle.visible_particles>0,"native nested drone muzzle has live source particles")
 if props._active.has(1):
  var item:Dictionary=props._active[1]
  var expected:Transform3D=item.skeleton.global_transform*item.skeleton.get_bone_global_pose(item.bone)*Transform3D(Props.PARTICLE_BRIDGE,Vector3.ZERO)
  var actual:Transform3D=props._resolve_muzzle({}, {}, 4.0, 1)
  ck(actual.is_equal_approx(expected),"nested source resolver matches actual live bone including yaw and scale")
  ck(item.container.global_transform.is_equal_approx(view._model.global_transform),"X-reflected prop does not receive particle Y-pi bridge")
 props.update_time(4.0);ck(snap==props.snapshot(),"same clock leaves native prop and particles unchanged")
 props.consume(event,units);props.update_time(4.0);ck(props.diagnostics().active_props==1,"duplicate event cannot double spawn")
 var stale:Dictionary=event.duplicate();stale.event_id="stale";stale.generation=4
 props.consume(stale,units);ck(props.diagnostics().stale_events==1,"stale generation rejected")
 props.update_time(7.0);ck(props.diagnostics().active_props==0,"exact source six-second prop window closes")
 props.begin_roster({1:view},units,6)
 event.generation=6;event.tick=0;event.event_id="again";props.consume(event,units);props.update_time(0)
 ck(props.diagnostics().active_props==1,"new generation can replay")
 props.consume({"type":"death","actor_id":1,"tick":10,"generation":6},units);props.update_time(0.5)
 ck(props.diagnostics().active_props==0,"death releases prop and nested particles")
 props.consume({"type":"skill","ability":"ex","actor_id":1,"tick":1000,"generation":6,"event_id":"future"},units)
 props.reset(7);ck(props.diagnostics().active_props==0 and props.diagnostics().queued_events==0,"reset clears current and pending prop state")
 props.free();view.free()
 print("SKILL_PROPS_TESTS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
