extends SceneTree
## Regression: injected/window-bound input coordinates need not equal OS cursor position.
## Use the real viewport input path and real camera projection, without native actors.
const Stage=preload("res://scripts/battle_stage.gd")
var checks:=0
var failures:=0
var selected_events:Array=[]
var placement_events:Array=[]
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func click(point:Vector2,pressed:bool=true,button:int=MOUSE_BUTTON_LEFT)->void:
	var event:=InputEventMouseButton.new();event.position=point;event.button_index=button;event.pressed=pressed
	root.push_input(event,true)
func move(point:Vector2)->void:
	var event:=InputEventMouseMotion.new();event.position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)
func project(stage:Node3D,point:Vector2)->Vector2:
	return stage.camera.unproject_position(Vector3(point.x,0,point.y))
func run()->void:
	root.content_scale_size=Vector2i(1280,900)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var stage=Stage.new();root.add_child(stage)
	stage.units=[{"id":0,"team":0,"cell":Vector2(-1.6,4.7)},{"id":1,"team":0,"cell":Vector2(1.6,4.7)},{"id":7,"team":1,"cell":Vector2(0,-4.7)}]
	stage.selected.connect(func(id):selected_events.append(id))
	stage.placement_requested.connect(func(id,point):placement_events.append({"id":id,"point":point}))
	for dimensions in [Vector2i(1280,900),Vector2i(1180,812),Vector2i(1600,900)]:
		root.size=dimensions;await process_frame
		stage.set_selected(-1);stage.dragging=false;selected_events.clear();placement_events.clear()
		var stale_mouse:=root.get_mouse_position()
		click(project(stage,Vector2(-1.6,4.7)))
		ck(root.get_mouse_position()==stale_mouse,"window-bound input does not warp OS cursor at %s"%dimensions)
		ck(stage.selected_id==0 and selected_events==[0] and stage.dragging,"event-local foot click selects own unit at %s"%dimensions)
		var target:=Vector2(-3.2,3.7)
		move(project(stage,target))
		ck(placement_events.size()==1 and placement_events[0].id==0 and placement_events[0].point.distance_to(target)<0.01,"event-local drag projects requested world point at %s"%dimensions)
		click(project(stage,target),false)
		ck(not stage.dragging,"button release ends drag at %s"%dimensions)
		placement_events.clear();move(project(stage,Vector2(-4,3)))
		ck(placement_events.is_empty(),"motion after release does not place at %s"%dimensions)
		stage.set_selected(0)
		click(project(stage,Vector2(-4,3)))
		ck(placement_events.size()==1 and placement_events[0].point.distance_to(Vector2(-4,3))<0.01,"empty ground click uses event-local position at %s"%dimensions)
		click(project(stage,Vector2(-4,3)),false)
	root.size=Vector2i(1180,812);await process_frame
	var expected_client:=root.get_final_transform()*project(stage,Vector2(-1.6,4.7))
	ck(expected_client.distance_to(Vector2(554.3,454.9))<0.15,"1180x812 letterboxed viewport projects Yuuka feet to known client pixels")
	stage.set_selected(-1);stage.dragging=false
	click(root.get_final_transform().affine_inverse()*Vector2(555,451))
	ck(stage.selected_id==0,"observed client click at 555,451 selects Yuuka without pointer warping")
	click(Vector2(555,451),false)
	stage.set_selected(-1);stage.dragging=false;selected_events.clear();placement_events.clear()
	click(project(stage,Vector2(0,-4.7)))
	ck(stage.selected_id==-1 and selected_events.is_empty(),"enemy feet do not select an own unit")
	click(project(stage,Vector2(-1.6,4.7)),true,MOUSE_BUTTON_RIGHT)
	ck(stage.selected_id==-1,"right click does not select")
	for point in [Vector2(500,30),Vector2(1100,400),Vector2(500,700)]:click(point)
	ck(stage.selected_id==-1 and placement_events.is_empty(),"UI exclusion regions ignore placement")
	stage.preparation=false
	click(project(stage,Vector2(-1.6,4.7)))
	ck(stage.selected_id==-1 and selected_events.is_empty(),"combat ignores deployment input")
	stage.free();await process_frame
	print("DEPLOYMENT_EVENT_INPUT ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
