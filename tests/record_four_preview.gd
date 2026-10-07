extends "res://tests/visual_combat_harness.gd"
## Records actual displayed frames and monotonic timestamps; no offline frame stepping.
var recording:=false
var record_started:int=0
var last_capture:int=0
var recorded:Array=[]
var capture_pending:=false
var recording_done:=false
func _ready():
	team_size=4;opponent_offset=3;report_slug="four-recording"
	super._ready()
func _process(delta:float):
	super._process(delta)
	if recording_done or capture_pending:return
	if time<2.0:return
	var now:int=Time.get_ticks_usec()
	if not recording:recording=true;record_started=now
	if now-record_started>=14000000:
		recording_done=true
		var file=FileAccess.open("res://evidence/recording/frames.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(recorded));file.close();get_tree().quit();return
	if now-last_capture>=50000:
		capture_pending=true
		_capture_live()
func _capture_live():
	await RenderingServer.frame_post_draw
	var now:int=Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/recording"))
	var path:String="res://evidence/recording/frame-%05d.jpg"%recorded.size()
	get_viewport().get_texture().get_image().save_jpg(path,0.9)
	recorded.append({"path":path,"timestamp_us":now,"sim_time":time})
	last_capture=now;capture_pending=false
