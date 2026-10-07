extends SceneTree
const Session=preload("res://core/game_session.gd")
var failures:=0
var checks:=0
func ck(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+message)
func put(path:String,contents:String)->void:
	var file=FileAccess.open(path,FileAccess.WRITE)
	ck(file!=null,"test fixture file opens")
	if file!=null:file.store_string(contents);file.close()
func _initialize()->void:
	var source:="res://core/session_save_store.gd"
	ck(ResourceLoader.exists(source),"bounded durable session save store exists")
	if failures:quit(1);return
	var store=load(source)
	var root:="user://session-save-tests-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	ck(DirAccess.make_dir_recursive_absolute(root)==OK,"isolated save-test folder creates")
	var path:String=root+"/continue.json"
	var missing:Dictionary=store.read_save(path)
	ck(not missing.ok and missing.error=="save_not_found","missing save fails explicitly")
	var game=Session.new();game.new_game(17)
	var bought:Dictionary=game.command({"type":"buy_offer","slot":0})
	ck(bought.ok and game.command({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"disk fixture deploys a unit")
	var precise:=Vector2(-3.1234567,4.234567)
	ck(game.place(bought.unit_id,precise),"disk fixture has a precise manual position")
	var first:Dictionary=game.export_save().data
	ck(store.write_save(first,path).ok,"first checkpoint writes")
	var read:Dictionary=store.read_save(path)
	ck(read.ok and not read.recovered and read.source_path==path,"read selects main checkpoint")
	ck(game.restore_save(read.data).ok and game.export_save().data==first,"stored JSON roundtrips exactly")
	ck(game.positions[bought.unit_id]==precise,"disk serialization preserves exact float32 coordinates")
	ck(not FileAccess.file_exists(path+".bak"),"first write invents no previous checkpoint")
	game.command({"type":"refresh_shop"});var second:Dictionary=game.export_save().data
	ck(store.write_save(second,path).ok,"second checkpoint writes verified replacement")
	var previous:Dictionary=store.read_save(path+".bak")
	ck(previous.ok and game.restore_save(previous.data).ok and game.export_save().data==first,"previous save remains recoverable")
	read=store.read_save(path)
	ck(read.ok and game.restore_save(read.data).ok and game.export_save().data==second,"main contains latest checkpoint")
	var original:String=FileAccess.get_file_as_string(path)
	var backup:String=FileAccess.get_file_as_string(path+".bak")
	var invalid:Dictionary=second.duplicate(true);invalid.version=99
	ck(not store.write_save(invalid,path).ok,"write rejects incompatible schema before touching files")
	ck(FileAccess.get_file_as_string(path)==original and FileAccess.get_file_as_string(path+".bak")==backup,"invalid write preserves both checkpoint generations")
	invalid=second.duplicate(true);invalid.rules.players[0].name="x".repeat(store.MAX_BYTES)
	ck(not store.write_save(invalid,path).ok,"oversized write rejected")
	ck(FileAccess.get_file_as_string(path)==original and FileAccess.get_file_as_string(path+".bak")==backup,"oversized write leaves durable checkpoint unchanged")
	invalid=second.duplicate(true);invalid.positions={"u999999":[0,4]}
	ck(not store.write_save(invalid,path).ok,"write validates semantic placements")
	var future:Dictionary=second.duplicate(true);future.version=99
	var bad_placement:Dictionary=second.duplicate(true);bad_placement.positions={"unknown":[0,4]}
	var bad_cases:Array=["{broken",JSON.stringify({"version":99}),JSON.stringify(future),JSON.stringify(bad_placement),"[]","null","x".repeat(store.MAX_BYTES+1)]
	for corrupt in bad_cases:
		put(path,corrupt)
		read=store.read_save(path)
		ck(read.ok and read.recovered and read.source_path==path+".bak" and not read.warning.is_empty(),"bad main file recovers validated previous checkpoint")
		ck(game.restore_save(read.data).ok and game.export_save().data==first,"recovery returns prior canonical state")
		ck(FileAccess.get_file_as_string(path)==corrupt and FileAccess.get_file_as_string(path+".bak")==backup,"read never modifies malformed main or recovery source")
		var alone:String=root+"/no-backup-%d.json"%checks;put(alone,corrupt)
		ck(not store.read_save(alone).ok,"bad main without backup fails safely")
	# A corrupt current file cannot replace a good backup during a later save.
	ck(store.write_save(second,path).ok,"new checkpoint replaces corrupt main")
	ck(FileAccess.get_file_as_string(path+".bak")==backup,"good recovery copy survives overwrite of bad main")
	put(path,"bad");put(path+".bak","also bad")
	ck(not store.read_save(path).ok,"two invalid generations fail instead of fabricating state")
	# A directory deliberately blocks temporary output without altering user data.
	var blocked:String=root+"/blocked.json";put(blocked,original);put(blocked+".bak",backup)
	ck(DirAccess.make_dir_recursive_absolute(blocked+".tmp")==OK,"write-failure fixture creates")
	ck(not store.write_save(first,blocked).ok,"temporary-write error reported")
	ck(FileAccess.get_file_as_string(blocked)==original and FileAccess.get_file_as_string(blocked+".bak")==backup,"temporary-write failure preserves main and backup")
	# Backup failure must also leave the main untouched.
	var backup_blocked:String=root+"/backup-blocked.json";put(backup_blocked,original)
	ck(DirAccess.make_dir_recursive_absolute(backup_blocked+".bak.tmp")==OK,"backup failure fixture creates")
	ck(not store.write_save(first,backup_blocked).ok,"backup creation error reported")
	ck(FileAccess.get_file_as_string(backup_blocked)==original,"backup failure preserves current save")
	var missing_main:String=root+"/missing-main.json";put(missing_main+".bak",backup)
	read=store.read_save(missing_main)
	ck(read.ok and read.recovered and read.source_path==missing_main+".bak","missing main can recover a valid previous checkpoint")
	var rename_blocked:String=root+"/backup-rename-blocked.json";put(rename_blocked,original)
	ck(DirAccess.make_dir_recursive_absolute(rename_blocked+".bak")==OK,"backup replacement failure fixture creates")
	ck(not store.write_save(first,rename_blocked).ok and FileAccess.get_file_as_string(rename_blocked)==original,"backup replacement failure leaves main intact")
	var main_blocked:String=root+"/main-rename-blocked.json"
	ck(DirAccess.make_dir_recursive_absolute(main_blocked)==OK,"main replacement failure fixture creates")
	ck(not store.write_save(first,main_blocked).ok and DirAccess.dir_exists_absolute(main_blocked),"final rename failure reports error and preserves existing destination")
	ck(store.read_save(main_blocked+".tmp").ok,"failed replacement retains a verified temporary checkpoint")
	ck(not store.write_save(first,root+"/missing-parent/save.json").ok,"unwritable path reports error without creating directories")
	print("SESSION SAVE STORE ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
