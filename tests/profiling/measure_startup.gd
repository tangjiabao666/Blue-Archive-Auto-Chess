extends SceneTree
func _initialize():call_deferred("run")
func run():
 var skip:bool="skip" in OS.get_cmdline_user_args()
 if skip:preload("res://scripts/render_warmup.gd").completed=true
 var creation_start:int=Time.get_ticks_usec()
 var app=load("res://tests/profiling/startup_app.gd").new();root.add_child(app);await process_frame
 while app.warming:await process_frame
 app.set_process(false)
 root.title="Blue-A | Startup profile"
 var ready_us:int=Time.get_ticks_usec()-creation_start
 var rows:Array=[]
 for index in range(2):
  app.act({"type":"restart","seed":17});app.session.rules._prepare_ai(app.session.rules._player_ref("p0"));app._refresh(true)
  await RenderingServer.frame_post_draw
  var before:int=Time.get_ticks_usec();var result:Dictionary=app.session.command({"type":"start_battle"});var session_us:int=Time.get_ticks_usec()-before
  if not result.ok:printerr(result);quit(1);return
  before=Time.get_ticks_usec();app._refresh(true);var refresh_us:int=Time.get_ticks_usec()-before
  rows.append({"iteration":index,"session_us":session_us,"refresh_us":refresh_us,"stage":app.stage.profile_last,"jobs":app.session.ai_battle_status()})
  await RenderingServer.frame_post_draw
 var report={"skip_warmup":skip,"ready_us":ready_us,"warmup":preload("res://scripts/render_warmup.gd").last_report,"rows":rows}
 var out="res://evidence/startup-profile/"+("skipped" if skip else "normal")+".json"
 var f=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print("STARTUP_PROFILE ",JSON.stringify(report))
 app.queue_free();await process_frame;quit()
