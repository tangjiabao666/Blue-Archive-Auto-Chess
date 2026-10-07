extends SceneTree
const Session=preload('res://core/game_session.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func snap(game)->Dictionary:return {'rules':game.rules.snapshot(),'positions':game.positions.duplicate(true),'manual':game.manual_positions.duplicate(true),'generation':game.clock.generation}
func _initialize()->void:
 var game=Session.new();game.new_game(23,'tactical_v1')
 ck(game.has_method('deploy_at'),'atomic bench deployment exists')
 if failures:finish();return
 var bought:Dictionary=game.command({'type':'buy_offer','slot':0});var id:String=bought.unit_id
 var point:=Vector2(0,4.7);var before:Dictionary=snap(game)
 for bad in [Vector2(0,-2),Vector2(99,99),Vector2(NAN,0),Vector2(INF,0),Vector2(0,3.5)]:
  ck(not game.deploy_at(id,bad).ok and snap(game)==before,'illegal terrain drop leaves complete state unchanged')
 ck(not game.deploy_at('not_owned',point).ok and snap(game)==before,'unowned drop atomic')
 ck(game.deployment_preview(id,point).ok and snap(game)==before,'valid preview never mutates')
 ck(game.deploy_at(id,point).ok and id in game.rules.get_player().deployed and game.positions[id]==point and game.manual_positions[id],'single drop deploys and places once')
 before=snap(game);ck(not game.deploy_at(id,point+Vector2(1,0)).ok and snap(game)==before,'duplicate drop cannot move or double deploy')
 var second:Dictionary=game.command({'type':'buy_offer','slot':2});var other:String=second.unit_id
 before=snap(game);ck(not game.deploy_at(other,point).ok and snap(game)==before,'overlap rejects atomically')
 ck(game.deploy_at(other,Vector2(2,4.7)).ok and game.positions[id]==point,'later drop preserves previous placement')
 var saved:Dictionary=game.export_save();var peer=Session.new();ck(saved.ok and peer.restore_save(saved.data).ok and peer.positions==game.positions,'drag deployment persists and reloads')
 var third:Dictionary=game.command({'type':'buy_offer','slot':1});var pending:String=third.unit_id
 ck(game.command({'type':'start_battle'}).ok,'battle begins during pending drag')
 before=snap(game);ck(not game.deploy_at(pending,Vector2(4,4.7)).ok and snap(game)==before,'battle-started drop rejects without state changes')
 var full=Session.new();full.new_game(29,'tactical_v1');var ids:Array=[]
 for slot in range(5):ids.append(full.command({'type':'buy_offer','slot':slot}).unit_id)
 for index in range(4):ck(full.deploy_at(ids[index],Vector2(-4+index*2,5.3)).ok,'fill legal four-person population')
 before=snap(full);ck(not full.deploy_at(ids[4],Vector2(4,5.3)).ok and snap(full)==before,'full population drop is atomic')
 ck(full.command({'type':'sell_unit','unit_id':ids[4]}).ok,'pending drag character sold')
 before=snap(full);ck(not full.deploy_at(ids[4],Vector2(4,5.3)).ok and snap(full)==before,'sold pending drag rejects atomically')
 finish()
func finish()->void:print('BENCH_DEPLOY checks=',checks,' failures=',failures);quit(1 if failures else 0)
