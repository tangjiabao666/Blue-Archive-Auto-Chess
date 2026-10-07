extends SceneTree
## Verify explicit bounded tail-only phase. No device output.
const Skills=preload("res://scripts/native_combat_audio.gd")
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func event(actor:int,tick:int,id:String)->Dictionary:
 return {"type":"skill","ability":"ex","actor_id":actor,"tick":tick,"generation":8,"event_id":id}
func _initialize():call_deferred("run")
func run():
 var audio=Skills.new();audio.output_enabled=false;root.add_child(audio)
 audio.begin_roster([{"id":0,"character_id":"shiroko","hp":100},{"id":1,"character_id":"hoshino","hp":100}],8)
 audio.consume(event(0,0,"final-burst"));audio.consume(event(1,0,"old-cast"));audio.update_time(0.05)
 ck(audio.diagnostics().active_voices>0,"a verified already-started one-shot exists at final impact")
 ck(audio.has_method("begin_tail_drain"),"explicit begin_tail_drain(cutoff, max_tail_seconds) API exists")
 if audio.has_method("begin_tail_drain"):
  audio.call("begin_tail_drain",0.1,0.8);audio.update_time(0.1)
  ck(audio.diagnostics().active_voices>0,"result transition preserves already-started one-shot tail")
  ck(audio.diagnostics().queued_events==0,"future EX reload/drop cues cannot start after combat cutoff")
  var count=audio.diagnostics().scheduled_count
  audio.consume(event(0,3,"late-cast"));audio.update_time(0.2)
  ck(audio.diagnostics().scheduled_count==count,"tail-only result rejects fresh cast onset")
  var before=audio.diagnostics();audio.update_time(2.0,true)
  ck(audio.diagnostics().time==before.time and audio.diagnostics().active_voices==before.active_voices,"pause freezes remaining tail")
  audio.update_time(1.0,false)
  ck(audio.diagnostics().active_voices==0 and audio.diagnostics().queued_events==0,"bounded tail phase drains completely")
  audio.reset(9);audio.update_time(10.0)
  ck(audio.diagnostics().active_voices==0 and audio.diagnostics().queued_events==0,"restart clears result tail and pending state")
 audio.free();await process_frame
 print("RESULT_AUDIO_TAIL checks=",checks," failures=",failures)
 quit(1 if failures else 0)
