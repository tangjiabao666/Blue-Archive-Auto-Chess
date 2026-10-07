extends SceneTree
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr(label)
func _initialize():call_deferred("run")
func run():
	var game=load("res://core/game_session.gd").new()
	var stage=load("res://scripts/battle_stage.gd").new();root.add_child(stage);stage.configure(game.profiles,game.OBSTACLES)
	var unit=game.clock.sim.preview_unit("yuuka",2,0,0,Vector2.ZERO)
	stage.set_roster([unit],1,false)
	ck(stage.bars[0].has("status"),"world HUD includes skill/buff status")
	if not fails:
		unit.shield=420;unit.shield_until=100
		stage.update_display([unit],[],1.0)
		ck(stage.bars[0].status.tooltip_text.contains("420"),"world HUD follows shield state")
		stage.update_display([unit],[],1.0)
		ck(stage.bars[0].status.status.ex.remaining_seconds==maxi(0,unit.skill_ready-20)*0.05,"pause keeps exact cooldown")
		await _test_tracking_root(stage,unit)
		unit.hp=0;stage.update_display([unit],[],2.0)
		ck(not stage.bars[0].status.visible,"death removes skill icons")
	stage.queue_free();await process_frame
	print("BATTLE STATUS OVERLAY FAILURES=",fails);quit(1 if fails else 0)

func _test_tracking_root(stage,unit:Dictionary)->void:
	var anchors:Dictionary={0:Vector2(400,300)}
	stage.inspection_id=0;stage._layout_status_overlays(anchors,1.1)
	var bar:Dictionary=stage.bars[0]
	var positions:Dictionary={}
	for key in ["label","hp","status","hit"]:positions[key]=bar[key].global_position
	var start:Vector2=bar.root.position
	anchors[0]+=Vector2(12,8);stage._layout_status_overlays(anchors,1.14)
	ck(bar.root.position.is_equal_approx(start+Vector2(12,8)),"real HUD moves between capped solver ticks")
	for key in positions:
		ck(bar[key].global_position.is_equal_approx(positions[key]+Vector2(12,8)),key+" shares the rendered HUD root")
	ck(bar.hit.get_global_rect().is_equal_approx(Rect2(bar.root.position+stage.STATUS_OFFSET,stage.STATUS_SIZE)),"complete click rectangle covers actual rendered HUD")
	ck((bar.leader.global_position+bar.leader.points[1]).is_equal_approx(anchors[0]+Vector2(30,0)),"real leader points to current actor after tracking")
	var inspected:Array=[]
	stage.inspected.connect(func(id):inspected.append(id))
	await process_frame
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=bar.hit.get_global_rect().get_center();root.push_input(click,true)
	ck(inspected==[0] and stage.selected_id==-1 and not stage.dragging,"tracked HUD hit still inspects without battle orders")
	# Same actor identity in a new generation must never inherit motion history.
	stage.set_roster([unit],2,false)
	ck(stage.bars[0].root!=bar.root,"generation reset rebuilds actual HUD root")
	ck(stage.bars[0].root.position.is_equal_approx(stage._status_layout_rects[0].position-stage.STATUS_OFFSET),"generation reset immediately displays fresh solved position")
	ck(stage._status_display_time==0.0 and stage._status_layout_time==0.0,"generation reset restores overlay battle-time origin")
