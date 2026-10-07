extends SceneTree
## Headless deploy/bench-equivalent cycles with a full scouted enemy roster.
const Sim=preload("res://core/character_sim.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var sim=Sim.new()
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	var script_path:String="res://scripts/battle_stage.gd"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--stage-script="):script_path=argument.trim_prefix("--stage-script=")
	var stage=load(script_path).new();root.add_child(stage);stage.configure(profiles,[])
	var characters:Array=["shiroko","hoshino","hina","aru","yuuka","aris","serika"]
	var roster:Array=[]
	for team in 2:
		for slot in 7:
			var value:Dictionary=sim.preview_unit(characters[slot],1,slot+team*7,team,Vector2(slot-3,3 if team==0 else -3))
			value.roster_unit_id="%s:%s"%[team,slot];roster.append(value)
	var extra:Dictionary=roster[6];roster.remove_at(6)
	stage.set_roster(roster,30,true)
	await process_frame
	var times:Array[float]=[];var replacements:=0;var retained:=0
	var cycles:=8
	for iteration in cycles*2:
		# Real preparation UI animates between commands and resets visual_time.
		stage.update_display(roster,[],0.35,0)
		var previous:Dictionary={}
		for id in stage.views:previous[id]=stage.views[id].get_instance_id()
		if iteration%2==0:roster.insert(6,extra)
		else:roster.remove_at(6)
		var start:=Time.get_ticks_usec()
		stage.set_roster(roster,30,true)
		times.append((Time.get_ticks_usec()-start)/1000.0)
		for id in stage.views:
			if previous.get(id,-1)==stage.views[id].get_instance_id():retained+=1
			else:replacements+=1
		await process_frame
	var total:=0.0
	for ms in times:total+=ms
	times.sort()
	print("PREPARATION_REUSE_BENCHMARK script=",script_path," cycles=",cycles," roster=13/14 refreshes=",times.size()," mean_ms=",total/times.size()," median_ms=",times[times.size()/2]," max_ms=",times[-1]," created=",replacements," retained=",retained)
	stage.free();await process_frame;quit()
