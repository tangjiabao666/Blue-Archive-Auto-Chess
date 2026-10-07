extends SceneTree
const Session=preload("res://core/game_session.gd")
func _initialize():
	DirAccess.make_dir_recursive_absolute("res://evidence/overtime")
	var seeds:Array=[17,20261002,1,42,99,1729]
	var enabled:=true
	for arg in OS.get_cmdline_user_args():
		if arg=="--disabled":enabled=false
		elif arg.begins_with("--seeds="):
			seeds=[]
			for value in arg.trim_prefix("--seeds=").split(","):seeds.append(int(value))
	var total_timeouts:=0
	for seed_value in seeds:
		var game=Session.new();game.new_game(seed_value)
		var rounds:=0;var timeouts:=0;var overtime_rounds:=0;var longest:=0.0
		while game.phase()!="finished" and rounds<40:
			game.rules._prepare_ai(game.rules._player_ref("p0"))
			var started:Dictionary=game.command({"type":"start_battle"})
			if not started.ok:printerr(started);quit(2);return
			var sim=game.clock.sim
			var settings:Dictionary=sim.options.duplicate(true)
			settings.overtime_enabled=enabled
			var rows:Array=game._battle_roster(started.battle)
			sim.phase="prepare"
			var error:String=sim.configure(rows,settings)
			if not error.is_empty():printerr(error);quit(2);return
			sim.start()
			var late_counts:Dictionary={};var finish_reason:=""
			while game.phase()=="battle":
				for event in game.advance(0.05):
					if event.type=="overtime_started":overtime_rounds+=1
					if event.tick>1500:late_counts[event.type]=late_counts.get(event.type,0)+1
					if event.type=="finished":
						finish_reason=event.reason
						if event.reason=="timeout":timeouts+=1
			var duration:float=sim.tick*0.05;longest=maxf(longest,duration)
			if duration>=75.0:
				print("LONG_ROUND ",JSON.stringify({"seed":seed_value,"round":rounds+1,"seconds":duration,"reason":finish_reason,"winner":sim.winner,"late_events":late_counts,"survivors":sim.units.filter(func(u):return u.hp>0).map(func(u):return {"character":u.character_id,"team":u.team,"hp":u.hp,"shield":u.shield})}))
			if duration>=75.0:
				var serialized:Array=[]
				for row in rows:
					var item:Dictionary=row.duplicate(true);item.cell=[row.cell.x,row.cell.y];serialized.append(item)
				var file=FileAccess.open("res://evidence/overtime/seed%d-round%d-roster-%s.json"%[seed_value,rounds+1,"overtime" if enabled else "native"],FileAccess.WRITE)
				file.store_string(JSON.stringify({"roster":serialized,"seed":seed_value+rounds+1,"round":rounds+1},"\t"))
			rounds+=1
			if game.phase()=="result":game.command({"type":"next_round"})
		print("MATCH ",JSON.stringify({"seed":seed_value,"rounds":rounds,"timeouts":timeouts,"overtime_rounds":overtime_rounds,"longest_seconds":longest,"placement":game.rules.snapshot().placement,"terminal":game.phase()=="finished","overtime_enabled":enabled}))
		total_timeouts+=timeouts
	print("PROBE_TIMEOUTS=",total_timeouts);quit(1 if total_timeouts else 0)
