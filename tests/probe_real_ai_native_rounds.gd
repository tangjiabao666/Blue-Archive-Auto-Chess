extends SceneTree
## Native acceptance only: use the actual app, source renderer and automatic battle clock.
var failures:=0
func ck(ok:bool,label:String):
 if not ok:failures+=1;printerr(label)
func _initialize():call_deferred("run")
func run():
 preload("res://scripts/render_warmup.gd").completed=true
 var app=load("res://scripts/gameplay.tscn").instantiate();root.add_child(app);await process_frame
 root.title="Blue-A | Real AI native acceptance"
 app.act({"type":"restart","seed":17})
 var records:Array=[]
 for index in range(2):
  app.session.rules._prepare_ai(app.session.rules._player_ref("p0"));app._refresh(true)
  await process_frame
  var before:int=Time.get_ticks_usec();var started:Dictionary=app.act({"type":"start_battle"});var startup_us:int=Time.get_ticks_usec()-before
  ck(started.ok,"native round starts")
  if not started.ok:break
  var max_pending:=0;var frames:=0;var deadline:int=Time.get_ticks_msec()+180000
  while app.session.phase()=="battle" and Time.get_ticks_msec()<deadline:
   max_pending=maxi(max_pending,int(app.session.ai_battle_status().pending));frames+=1
   await process_frame
  ck(app.session.phase() in ["result","finished"],"native battle reaches result")
  if app.session.phase() not in ["result","finished"]:break
  var state:Dictionary=app.session.rules.snapshot()
  for row in state.last_result.ai_results:ck(row.resolution=="simulation","native result uses source simulation")
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://evidence/real-ai-native/round-%d.png"%[index+1])
  var record:Dictionary={"round":state.last_result.round,"startup_us":startup_us,"max_pending":max_pending,"frames":frames,"jobs":app.session.ai_battle_status(),"ai_results":state.last_result.ai_results,"visible_duration_seconds":app.session.clock.sim.tick*0.05,"status_text":app.status.text}
  records.append(record);print("NATIVE_REAL_AI_ROUND ",JSON.stringify(record))
  if index==0:ck(app.act({"type":"next_round"}).ok,"native result advances to preparation")
 var f=FileAccess.open("res://evidence/real-ai-native/receipt.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures,"rounds":records},"  "));f.close()
 app.queue_free();await process_frame
 print("NATIVE_REAL_AI FAILURES=",failures);quit(1 if failures else 0)
