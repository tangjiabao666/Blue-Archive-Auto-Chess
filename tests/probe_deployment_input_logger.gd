extends Node
var app:Node
func _input(event:InputEvent)->void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		var root=get_viewport();var stage=app.stage
		var distances=[];var point=stage._mouse_ground()
		for unit in stage.units:
			if unit.team!=0:continue
			distances.append({"id":unit.id,"cell":str(unit.cell),"screen":str(stage.camera.unproject_position(Vector3(unit.cell.x,0,unit.cell.y))),"distance":point.distance_to(unit.cell) if point!=null else -1})
		var hovered=root.gui_get_hovered_control()
		print("INPUT PROBE ",JSON.stringify({"pressed":event.pressed,"event_position":str(event.position),"mouse":str(root.get_mouse_position()),"ground":str(point),"event_ground":str(stage._mouse_ground(event.position)),"hovered":str(hovered.get_path()) if hovered else "none","window_size":str(root.size),"visible":str(root.get_visible_rect()),"final_transform":str(root.get_final_transform()),"selected_before":stage.selected_id,"distances":distances}))
		call_deferred("after_event")
func _unhandled_input(event:InputEvent)->void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:print("UNHANDLED PROBE pressed=",event.pressed," position=",event.position)
func after_event()->void:print("AFTER PROBE selected=",app.stage.selected_id," owned=",app.selected_owned," dragging=",app.stage.dragging)
