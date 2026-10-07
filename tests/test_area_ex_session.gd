extends SceneTree
const Session=preload("res://core/game_session.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func _initialize():
 var game=Session.new();ck(game.new_game(17).ok,"session starts")
 for left in range(8):
  for right in range(8):
   if left==right:continue
   ck(game._battle_options(17,"p%d"%left,"p%d"%right).get("area_ex_coverage_targeting",false)==true,"all participant pairings receive same coverage policy")
 game.rules._prepare_ai(game.rules._player_ref("p0"))
 game._sync_positions()
 var saved:Dictionary=game.export_save().data
 var restored=Session.new();ck(restored.restore_save(saved).ok,"existing preparation save restores")
 ck(restored._battle_options(17,"p0","p1").get("area_ex_coverage_targeting",false)==true,"restored matches use current automatic EX policy")
 var begun:Dictionary=game.command({"type":"start_battle"});ck(begun.ok,"visible and offscreen battles start")
 if begun.ok:
  ck(game.clock.sim.options.get("area_ex_coverage_targeting",false)==true,"visible simulation enabled")
  for record in game._ai_jobs:
   record.job.advance(1)
   ck(record.job._simulation.options.get("area_ex_coverage_targeting",false)==true,"offscreen simulation enabled")
 print("AREA_EX_SESSION ",checks," checks; ",failures," failures");quit(1 if failures else 0)
