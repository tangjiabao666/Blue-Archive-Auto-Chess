extends SceneTree
func _initialize():call_deferred("run")
func run():
	preload("res://scripts/render_warmup.gd").completed=true
	var app=load("res://scripts/gameplay.tscn").instantiate();root.add_child(app);await process_frame
	app.act({"type":"restart","seed":1})
	var p=app.session.rules._player_ref("p0")
	p.gold=100
	for i in range(3):
		var key=["yuuka","aris","iori"][i]
		p.shop[i]={"character_id":key,"cost":app.session.COSTS[key]}
		var bought=app.act({"type":"buy_offer","slot":i});app.act({"type":"deploy_unit","unit_id":bought.unit_id})
	var probe=load("res://tests/probe_deployment_input_logger.gd").new();probe.app=app;root.add_child(probe)
	root.title="Blue-A | Input diagnostic"
	print("INPUT PROBE READY")
	for unit in app.stage.units:
		if unit.team==0:print("UNIT id=",unit.id," cell=",unit.cell," feet=",app.stage.camera.unproject_position(Vector3(unit.cell.x,0,unit.cell.y)))
