extends SceneTree
const Session=preload('res://core/game_session.gd')
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 var session=Session.new();ck(session.new_game(23,'tactical_v1').ok,'new tactical match configures')
 var values:Dictionary=session._battle_options(1,'p0','p1')
 ck(values.get('max_ticks')==1800,'new battle cap is90seconds')
 ck(values.get('overtime_start_seconds')==60.0,'overtime starts60seconds')
 ck(values.get('overtime_ramp_seconds')==10.0,'short profile reaches its overtime endpoint by70seconds')
 for old_profile in [1,2]:
  var old:Dictionary=preload('res://core/battle_pacing.gd').options(old_profile)
  ck(old.overtime_ramp_seconds==30.0 and old.overtime_start_seconds==75.0 and old.max_ticks==3000,'old pacing profile remains exact')
 ck(values.get('timeout_total_hp',false),'new profile decides timeouts by totalHP')
 ck(session.rules_profile()==3,'new profile is explicit')
 ck(session.rules.snapshot().config.max_level==5,'five-unit population unchanged')
 var saved:Dictionary=session.export_save();ck(saved.ok,'new save exports')
 if saved.ok:
  ck(saved.data.version==10,'new envelope version10')
  var restored=Session.new();ck(restored.restore_save(saved.data).ok,'new checkpoint roundtrips')
  ck(restored._battle_options(1,'p0','p1')==values,'restored new profile keeps combat settings')
 print('SHORT_ROUND_PROFILE checks=',checks,' failures=',failures);quit(1 if failures else 0)
