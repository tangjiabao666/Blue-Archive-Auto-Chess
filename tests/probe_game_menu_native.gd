extends SceneTree
## Isolated native UI acceptance: never reads/writes the user's normal saves.
const App=preload("res://scripts/game_app.gd")
var app:Node
var output:String="res://evidence/delivery/ui"
var last:Dictionary={}
var next_record:int=0
var sequence:int=0
func _initialize():call_deferred("run")
func run():
 var run_id:String=Time.get_datetime_string_from_system().replace(":","-")+"-"+str(Time.get_ticks_usec())
 output=output.path_join(run_id)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 FileAccess.open("res://evidence/delivery/ui/latest.txt",FileAccess.WRITE).store_string(output)
 preload("res://scripts/render_warmup.gd").completed=true
 app=App.new();app.persistence_enabled=true
 app.save_path=output.path_join("qa-session-"+str(Time.get_ticks_usec())+".json")
 app.settings_path=output.path_join("qa-settings-"+str(Time.get_ticks_usec())+".cfg")
 root.add_child(app)
 DisplayServer.window_set_title("Blue-A Delivery UI QA")
 process_frame.connect(record)
 record()
func record():
 if Time.get_ticks_msec()<next_record or not is_instance_valid(app):return
 next_record=Time.get_ticks_msec()+250
 var player:Dictionary=app.session.rules.get_player()
 var snapshot:Dictionary={"phase":app.session.phase(),"paused":app.session.paused,"generation":app.session.clock.generation,"menu":app.game_menu.visible,"gold":player.gold,"owned":player.units.size(),"deployed":player.deployed.size(),"settings":app.settings_values.duplicate(true),"save_exists":FileAccess.file_exists(app.save_path),"notice":app.notice.text,"message":app.game_menu.message.text,"window_mode":DisplayServer.window_get_mode(),"master_muted":AudioServer.is_bus_mute(0),"save_path":app.save_path,"settings_path":app.settings_path}
 if snapshot==last:return
 last=snapshot
 FileAccess.open(output.path_join("state.json"),FileAccess.WRITE).store_string(JSON.stringify(snapshot,"  "))
 var file=FileAccess.open(output.path_join("actions.jsonl"),FileAccess.READ_WRITE) if FileAccess.file_exists(output.path_join("actions.jsonl")) else FileAccess.open(output.path_join("actions.jsonl"),FileAccess.WRITE)
 file.seek_end();file.store_line(JSON.stringify(snapshot));file.close()
 print("DELIVERY_UI_STATE ",JSON.stringify(snapshot))
 sequence+=1;capture.call_deferred(sequence)
func capture(index:int):
 await RenderingServer.frame_post_draw
 if is_instance_valid(app):root.get_texture().get_image().save_png(output.path_join("frame-%03d.png"%index))
