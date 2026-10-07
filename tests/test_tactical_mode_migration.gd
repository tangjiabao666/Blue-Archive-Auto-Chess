extends SceneTree
const Session=preload('res://core/game_session.gd')
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 var s=Session.new()
 ck(s.has_method('combat_mode'),'session exposes explicit combat mode')
 if failures:finish();return
 ck(s.call('new_game',23,'tactical_v1').ok and s.combat_mode()=='tactical_v1','new tactical session')
 var preview:Dictionary=s.clock.sim.preview_unit('hina',2)
 ck(preview.skill_ready==0 and preview.skill_cooldown_ticks==120,'tactical recruitment preview shows actual EX cooldown')
 var save:Dictionary=s.export_save()
 ck(save.ok and save.data.version==10 and save.data.combat_mode=='tactical_v1','save10 carries mode terrain and match format')
 var restored=Session.new()
 ck(restored.restore_save(save.data).ok and restored.combat_mode()=='tactical_v1','tactical round trip')
 var original:Dictionary=restored.export_save().data
 for value in ['future',17,true,null]:
  var bad:Dictionary=save.data.duplicate(true);bad.combat_mode=value
  ck(not restored.restore_save(bad).ok and restored.export_save().data==original,'invalid mode atomic '+str(value))
 var missing:Dictionary=save.data.duplicate(true);missing.erase('combat_mode')
 ck(not restored.restore_save(missing).ok,'Save6 cannot omit mode')
 for name in ['shop_retention_legacy_session_v1.json','normal_target_legacy_session_v2.json','reinforcement_legacy_session_v3.json','asuna_legacy_session_v4_pending.json','tactical_legacy_session_v5.json']:
  var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/'+name))
  var before:Dictionary=old.duplicate(true)
  ck(restored.restore_save(old).ok and restored.combat_mode()=='legacy','legacy mode '+name)
  ck(old==before,'input fixture unchanged '+name)
  ck(restored.export_save().data.combat_mode=='legacy','saved legacy remains legacy '+name)
 ck(s.command({'type':'restart','seed':24}).ok and s.combat_mode()=='tactical_v1','restart retains chosen mode')
 var state:Dictionary=s.export_save().data
 ck(not s.call('new_game',25,'bad').ok and s.export_save().data==state,'invalid new mode atomic')
 var projection=load('res://tests/tactical_save_projection.gd')
 var legacy=Session.new();legacy.new_game(23)
 var canonical:Dictionary=legacy.export_save().data
 ck(projection.legacy_envelope(canonical).version==5,'strict legacy inverse')
 for patch in [{'combat_mode':'tactical_v1'},{'version':5},{'extra':0}]:
  var wrong:Dictionary=canonical.duplicate(true);wrong.merge(patch,true)
  ck(projection.legacy_envelope(wrong).is_empty(),'inverse rejects changed schema '+str(patch))
 finish()
func finish()->void:
 print('TACTICAL_MODE_MIGRATION checks=',checks,' failures=',failures);quit(1 if failures else 0)
