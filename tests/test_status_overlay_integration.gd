extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,msg:String):
 checks+=1
 if not ok:failures+=1;printerr(msg)
func _initialize():call_deferred("run")
func run():
 var stage=load("res://scripts/battle_stage.gd").new();root.add_child(stage)
 ck(stage.has_method("_layout_status_overlays"),"status layout integration exists")
 if not stage.has_method("_layout_status_overlays"):stage.free();finish();return
 var anchors:Dictionary={}
 for id in range(12):
  var holder:=Control.new();stage.hud.add_child(holder)
  var leader:=Line2D.new();holder.add_child(leader)
  stage.bars[id]={"root":holder,"leader":leader}
  anchors[id]=Vector2(400+(id%4)*18,300+(id/4)*18)
 stage._layout_status_overlays(anchors,0.0)
 var before:Dictionary=stage._status_layout_rects.duplicate(true)
 for id in before:
  ck(Rect2(8,112,984,530).encloses(before[id]),"all overlays within field UI bounds")
  for other in before:
   if other>id:ck(not before[id].intersects(before[other]),"dense overlays do not overlap")
  ck(stage.bars[id].leader.points.size()==2,"leader has stable endpoints")
 stage._layout_status_overlays(anchors,0.02)
 ck(stage._status_layout_rects==before and stage._status_layout_time==0.0,"same input avoids recomputation below10Hz")
 anchors[0]+=Vector2(1,1);stage._layout_status_overlays(anchors,0.04)
 ck(stage._status_layout_time==0.0,"movement does not bypass cadence")
 stage._layout_status_overlays(anchors,0.11)
 ck(is_equal_approx(stage._status_layout_time,0.11),"moving layout refreshes at capped cadence")
 stage.inspection_id=0;stage._layout_status_overlays(anchors,0.12)
 ck(stage._status_layout_priority==0,"inspection priority refreshes immediately")
 anchors.erase(0);stage._layout_status_overlays(anchors,0.13)
 ck(not stage._status_layout_rects.has(0),"removed/dead actor no longer occupies layout")
 stage.free()
 _test_tracking();_test_offset_transition();_test_tracking_safety();_test_interpolation_safety();_test_selective_fallback();_test_cascading_fallback();_test_structural_tracking()
 finish()
func finish():print("OVERLAY INTEGRATION ",checks," checks; ",failures," failures");quit(1 if failures else 0)

# The solver remains capped; the actual controls must not inherit its 10 Hz steps.
class CountingLayout extends "res://core/status_overlay_layout.gd":
 var calls:=0
 func arrange(items:Array,bounds:Rect2,priority_id:int=-1)->Dictionary:
  calls+=1
  return super.arrange(items,bounds,priority_id)
func _tracking_stage(count:int):
 var stage=load("res://scripts/battle_stage.gd").new();root.add_child(stage)
 stage._overlay_layout=CountingLayout.new()
 for id in count:
  var holder:=Control.new();stage.hud.add_child(holder)
  var leader:=Line2D.new();holder.add_child(leader)
  var hit:=Control.new();hit.position=stage.STATUS_OFFSET;hit.size=stage.STATUS_SIZE;holder.add_child(hit)
  stage.bars[id]={"root":holder,"leader":leader,"hit":hit}
 return stage
func _rendered(stage,ids:Array)->Dictionary:
 var rects:Dictionary={}
 for id in ids:rects[id]=Rect2(stage.bars[id].root.position+stage.STATUS_OFFSET,stage.STATUS_SIZE)
 return rects
func _check_safe(stage,anchors:Dictionary,label:String)->void:
 var rects:Dictionary=_rendered(stage,anchors.keys())
 for id in rects:
  ck(stage.STATUS_BOUNDS.encloses(rects[id]),label+" stays in bounds")
  for other in rects:
   if other>id:ck(not rects[id].intersects(rects[other]),label+" avoids rendered overlaps")
  ck(stage.bars[id].hit.get_global_rect().is_equal_approx(rects[id]),label+" click target tracks rendered root")
  var line:Line2D=stage.bars[id].leader
  ck((line.global_position+line.points[1]).is_equal_approx(anchors[id]+Vector2(30,0)),label+" leader ends at current actor")
func _test_tracking()->void:
 var stage=_tracking_stage(12)
 var initial:Dictionary={}
 for id in 12:initial[id]=Vector2(400+(id%4)*18,300+(id/4)*18)
 stage._layout_status_overlays(initial,0.0)
 var start:Dictionary=_rendered(stage,initial.keys())
 var solved:Dictionary=stage._status_layout_rects.duplicate()
 for at in [0.016,0.033,0.066,0.1,0.116,0.15,0.199,0.2]:
  var anchors:Dictionary={}
  var delta:Vector2=Vector2(40,20)*at
  for id in initial:anchors[id]=initial[id]+delta
  stage._layout_status_overlays(anchors,at)
  for id in anchors:
   ck(stage.bars[id].root.position.is_equal_approx(start[id].position-stage.STATUS_OFFSET+delta),"dense cluster follows intermediate anchor motion without solver stepping")
  _check_safe(stage,anchors,"translated dense cluster")
  if at<0.1:ck(stage._status_layout_rects==solved,"rendered movement never mutates cached collision solution")
 ck(stage._overlay_layout.calls==3,"moving controls keep exactly the original 10 Hz solve cadence")
 stage.free()
func _test_offset_transition()->void:
 var direct=_tracking_stage(2)
 var split=_tracking_stage(2)
 var anchors:Dictionary={0:Vector2(400,300),1:Vector2(400,300)}
 for stage in [direct,split]:stage._layout_status_overlays(anchors,0.0)
 var displaced:Vector2=direct.bars[1].root.position
 ck(not displaced.is_equal_approx(anchors[1]),"offset fixture starts displaced by real collision solver")
 anchors[0]=Vector2(650,300)
 for stage in [direct,split]:stage._layout_status_overlays(anchors,0.1)
 ck(direct.bars[1].root.position.is_equal_approx(displaced),"new collision solution starts from previous visual offset")
 for at in [0.11,0.125,0.14]:split._layout_status_overlays(anchors,at)
 for stage in [direct,split]:stage._layout_status_overlays(anchors,0.15)
 var middle:Vector2=direct.bars[1].root.position
 ck(middle.is_equal_approx(displaced.lerp(anchors[1],0.5)),"collision-offset correction has an intermediate battle-time position")
 ck(split.bars[1].root.position.is_equal_approx(middle),"transition uses elapsed battle time rather than render-call partition")
 for repeat in 5:direct._layout_status_overlays(anchors,0.15)
 ck(direct.bars[1].root.position.is_equal_approx(middle),"pause does not advance the visual transition")
 _check_safe(direct,anchors,"intermediate offset correction")
 direct._layout_status_overlays(anchors,0.2)
 ck(direct.bars[1].root.position.is_equal_approx(anchors[1]),"stationary anchors finish an offset transition without another solve")
 ck(direct._overlay_layout.calls==2,"offset interpolation never reruns solver for stationary anchors")
 # This rewind is newer than the last solve, but older than the last display.
 split._layout_status_overlays(anchors,0.14)
 ck(split._overlay_layout.calls==3 and is_equal_approx(split._status_layout_time,0.14),"rewind within cached solve interval resets tracking immediately")
 ck(split.bars[1].root.position.is_equal_approx(anchors[1]),"rewind never reuses a future visual offset")
 direct.free();split.free()
func _test_tracking_safety()->void:
 var stage=_tracking_stage(2)
 var anchors:Dictionary={0:Vector2(350,300),1:Vector2(450,300)}
 stage._layout_status_overlays(anchors,0.0)
 var safe:Dictionary=_rendered(stage,anchors.keys())
 anchors[0]=Vector2(400,300);anchors[1]=Vector2(400,300)
 stage._layout_status_overlays(anchors,0.05)
 ck(_rendered(stage,anchors.keys())==safe,"colliding between-solve motion falls back to cached safe placement")
 _check_safe(stage,anchors,"crossing motion fallback")
 anchors[0]=Vector2(450,300);anchors[1]=Vector2(350,300)
 stage._layout_status_overlays(anchors,0.1)
 _check_safe(stage,anchors,"crossing motion new solution")
 ck(stage._overlay_layout.calls==2,"collision safety does not force extra solver calls")
 stage.free()
 stage=_tracking_stage(1)
 anchors={0:Vector2(24,200)}
 stage._layout_status_overlays(anchors,0.0)
 anchors[0]=Vector2(-200,200)
 stage._layout_status_overlays(anchors,0.05)
 _check_safe(stage,anchors,"out of bounds motion fallback")
 ck(stage._overlay_layout.calls==1,"bounds safety does not bypass solve cadence")
 stage.free()
func _test_interpolation_safety()->void:
 var stage=_tracking_stage(2)
 var anchors:Dictionary={0:Vector2(400,300),1:Vector2(400,300)}
 stage._layout_status_overlays(anchors,0.0)
 var old_offset:Vector2=stage.bars[1].root.position-anchors[1]
 anchors[0]=Vector2(400,260);stage._layout_status_overlays(anchors,0.1)
 var solved:Dictionary=stage._status_layout_rects.duplicate()
 var target_offset:Vector2=solved[1].position-stage.STATUS_OFFSET-anchors[1]
 var unsafe_middle:Rect2=Rect2(anchors[1]+stage.STATUS_OFFSET+old_offset.lerp(target_offset,0.5),stage.STATUS_SIZE)
 ck(unsafe_middle.intersects(solved[0]),"real solver fixture would cross another HUD during naive interpolation")
 for at in [0.1,0.125,0.15,0.175,0.2]:
  stage._layout_status_overlays(anchors,at)
  _check_safe(stage,anchors,"collision-offset crossing fallback")
 ck(stage._overlay_layout.calls==2,"unsafe interpolation never escalates to per-frame collision solves")
 stage.free()
func _test_selective_fallback()->void:
 var stage=_tracking_stage(3)
 var initial:Dictionary={0:Vector2(350,300),1:Vector2(450,300),2:Vector2(700,450)}
 stage._layout_status_overlays(initial,0.0)
 var solved:Dictionary=stage._status_layout_rects.duplicate()
 var anchors:Dictionary={0:Vector2(400,300),1:Vector2(400,300),2:Vector2(710,450)}
 stage._layout_status_overlays(anchors,0.05)
 for id in [0,1]:ck(stage.bars[id].root.position.is_equal_approx(initial[id]),"only colliding pair returns to cached roots")
 ck(stage.bars[2].root.position.is_equal_approx(anchors[2]),"unrelated third HUD keeps intermediate movement during pair fallback")
 ck(stage._status_layout_rects==solved and stage._overlay_layout.calls==1,"selective fallback neither changes solution nor bypasses cadence")
 _check_safe(stage,anchors,"selective pair fallback")
 stage.free()
 stage=_tracking_stage(3)
 initial={0:Vector2(24,200),1:Vector2(300,400),2:Vector2(600,400)}
 stage._layout_status_overlays(initial,0.0)
 anchors={0:Vector2(-200,200),1:Vector2(310,400),2:Vector2(620,400)}
 stage._layout_status_overlays(anchors,0.05)
 ck(stage.bars[0].root.position.is_equal_approx(initial[0]),"out of bounds HUD returns to its own cached root")
 for id in [1,2]:ck(stage.bars[id].root.position.is_equal_approx(anchors[id]),"one boundary HUD never freezes unrelated safe movement")
 _check_safe(stage,anchors,"selective boundary fallback")
 stage.free()
func _test_cascading_fallback()->void:
 var stage=_tracking_stage(4)
 var initial:Dictionary={0:Vector2(300,300),1:Vector2(400,300),2:Vector2(500,300),3:Vector2(700,450)}
 stage._layout_status_overlays(initial,0.0)
 # The third candidate is clear of both colliding candidates, but occupies the
 # first label's cached position. Snapping the pair must recheck that conflict.
 var anchors:Dictionary={0:Vector2(450,300),1:Vector2(450,300),2:Vector2(300,300),3:Vector2(710,450)}
 stage._layout_status_overlays(anchors,0.05)
 for id in [0,1,2]:ck(stage.bars[id].root.position.is_equal_approx(initial[id]),"fallback-induced conflict also returns to cached placement")
 ck(stage.bars[3].root.position.is_equal_approx(anchors[3]),"cascade never freezes an unrelated fourth HUD")
 _check_safe(stage,anchors,"cascading selective fallback")
 ck(stage._overlay_layout.calls==1,"cascade never asks expensive solver to repair per-frame motion")
 stage.free()
 stage=_tracking_stage(12)
 initial={}
 for id in 12:initial[id]=Vector2(180+(id%4)*100,220+(id/4)*90)
 stage._layout_status_overlays(initial,0.0)
 anchors={0:Vector2(850,500),1:Vector2(850,500),2:initial[0]}
 for id in range(3,12):anchors[id]=initial[id-1]
 stage._layout_status_overlays(anchors,0.05)
 for id in initial:ck(stage.bars[id].root.position.is_equal_approx(initial[id]),"max-roster fallback chain reaches every newly occupied cached slot")
 _check_safe(stage,anchors,"twelve HUD fallback chain")
 var before:Dictionary=_rendered(stage,anchors.keys())
 stage._layout_status_overlays(anchors,0.05)
 ck(_rendered(stage,anchors.keys())==before,"paused fallback chain is deterministic and stable")
 ck(stage._overlay_layout.calls==1,"maximum chain does not increase solver cadence")
 stage.free()
func _test_structural_tracking()->void:
 var stage=_tracking_stage(3)
 var anchors:Dictionary={0:Vector2(400,300),1:Vector2(400,300)}
 stage._layout_status_overlays(anchors,0.0)
 anchors[0]=Vector2(650,300);stage._layout_status_overlays(anchors,0.1)
 stage._layout_status_overlays(anchors,0.14)
 stage.inspection_id=1;stage._layout_status_overlays(anchors,0.15)
 ck(stage._overlay_layout.calls==3 and stage._status_layout_priority==1,"inspection priority bypasses solve cadence")
 ck(_rendered(stage,anchors.keys())==stage._status_layout_rects,"priority change clears in-flight visual offset")
 anchors.erase(0);stage._layout_status_overlays(anchors,0.16)
 ck(stage._overlay_layout.calls==4 and stage._status_layout_rects.keys()==[1],"death removes occupied tracking slot immediately")
 ck(_rendered(stage,anchors.keys())==stage._status_layout_rects,"death snaps to current safe solution")
 anchors[2]=Vector2(400,300);stage._layout_status_overlays(anchors,0.17)
 ck(stage._overlay_layout.calls==5,"new actor resets tracking before old cadence expires")
 _check_safe(stage,anchors,"new actor structural solution")
 stage.inspection_id=-1;stage.selected_id=2;stage._layout_status_overlays(anchors,0.18)
 ck(stage._status_layout_priority==2 and stage._overlay_layout.calls==6,"preparation selection remains immediate")
 var previous_size:Vector2i=root.content_scale_size
 root.content_scale_size=previous_size+Vector2i(80,40);stage._layout_status_overlays(anchors,0.19)
 ck(stage._overlay_layout.calls==7,"viewport change resets tracking immediately")
 ck(_rendered(stage,anchors.keys())==stage._status_layout_rects,"viewport change clears stale interpolated placement")
 root.content_scale_size=previous_size
 stage._layout_status_overlays({},0.2)
 ck(stage._status_layout_rects.is_empty(),"empty roster clears all solved slots")
 stage.free()
