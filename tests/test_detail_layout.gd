extends SceneTree
var fails:=0
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1280,900)
	var app=load("res://scripts/gameplay.tscn").instantiate();root.add_child(app);await process_frame
	app.set_process(false)
	for character in app.session.ACTIVE:
		for star in [1,2]:
			var p:Dictionary=app.session.rules._state.players[0]
			p.units=[{"id":"layout", "character_id":character,"star":star}];p.bench=["layout"];p.deployed=[]
			app.select_owned("layout");await process_frame
			var bottom:float=app.detail_scroll.position.y+app.detail_scroll.size.y
			if not app.detail_scroll.clip_contents or bottom>app.deploy_button.position.y-6:
				fails+=1;printerr("Character inspector viewport overlaps actions: ",character," star",star," bottom=",bottom)
			if app.detail.get_parent()!=app.detail_scroll or app.detail.size.x>app.detail_scroll.size.x:
				fails+=1;printerr("Character detail is not horizontally contained")
			app.detail_scroll.scroll_vertical=100000;await process_frame
			if app.detail.get_minimum_size().y>app.detail_scroll.size.y and app.detail_scroll.scroll_vertical<=0:
				fails+=1;printerr("Overflow character details cannot scroll: ",character)

	if app.standings.position.y+app.standings.get_minimum_size().y>app.report_button.position.y-4:
		fails+=1;printerr("Full eight-player standings overlap report button")
	app.queue_free();await process_frame
	print("DETAIL LAYOUT FAILURES=",fails);quit(1 if fails else 0)
