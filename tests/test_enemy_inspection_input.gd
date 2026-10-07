extends SceneTree
var checks:=0
var failures:=0
var inspections:Array=[]
var placements:Array=[]
var selected:Array=[]
func ck(ok:bool,msg:String):
 checks+=1
 if not ok:failures+=1;printerr(msg)
func _initialize():call_deferred("run")
func click(stage,point:Vector2):
 var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=stage.camera.unproject_position(Vector3(point.x,0,point.y));root.push_input(event,true)
func run():
 var args=OS.get_cmdline_user_args()
 var stage=load(args[0] if not args.is_empty() else "res://scripts/battle_stage.gd").new();root.add_child(stage)
 ck(stage.has_signal("inspected"),"actor inspection signal exists")
 if not stage.has_signal("inspected"):stage.free();finish();return
 stage.inspected.connect(func(id):inspections.append(id))
 stage.placement_requested.connect(func(id,point):placements.append([id,point]))
 stage.selected.connect(func(id):selected.append(id))
 stage.units=[{"id":0,"team":0,"cell":Vector2(-1.6,4.7),"hp":10},{"id":7,"team":1,"cell":Vector2(0,-4.7),"hp":10}]
 for dim in [Vector2i(1280,900),Vector2i(1152,810)]:
  root.size=dim;await process_frame
  stage.preparation=true;stage.set_selected(0);stage.dragging=true;inspections.clear();placements.clear();selected.clear()
  click(stage,Vector2(0,-4.7))
  ck(inspections==[7],"enemy click emits read-only inspection")
  ck(placements.is_empty() and selected.is_empty() and stage.selected_id==-1 and not stage.dragging,"enemy click cancels drag and never places previous ally")
  var move:=InputEventMouseMotion.new();move.button_mask=MOUSE_BUTTON_MASK_LEFT;move.position=stage.camera.unproject_position(Vector3(2,0,3));root.push_input(move,true)
  ck(placements.is_empty(),"motion after enemy inspection does not place")
  click(stage,Vector2(-1.6,4.7));ck(selected==[0] and stage.dragging,"own preparation selection remains usable")
  stage.preparation=false;stage.set_selected(-1);stage.dragging=false;inspections.clear();placements.clear();selected.clear()
  click(stage,Vector2(-1.6,4.7));click(stage,Vector2(0,-4.7))
  ck(inspections==[0,7] and selected.is_empty() and placements.is_empty() and not stage.dragging,"either battle team inspected without orders")
  stage.units[1].hp=0;inspections.clear();click(stage,Vector2(0,-4.7));ck(inspections.is_empty(),"dead actor not inspected")
  stage.units[1].hp=10
 stage.free();finish()
func finish():print("ENEMY INPUT ",checks," checks; ",failures," failures");quit(1 if failures else 0)
