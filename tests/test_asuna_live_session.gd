extends SceneTree
const Session=preload("res://core/game_session.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize():
 var game=Session.new();ck(game.new_game(23).ok,"natural seeded match starts")
 var start_gold:int=game.rules.get_player().gold
 for slot in [1,3,4]:
  ck(game.rules.get_player().shop[slot].character_id=="asuna","natural opening offers Asuna")
  ck(game.command({"type":"buy_offer","slot":slot}).ok,"buy Asuna through real shop command")
 var matches:Array=game.rules.get_player().units.filter(func(u):return u.character_id=="asuna")
 ck(matches.size()==1 and matches[0].star==2 and matches[0].ex_enabled,"three purchased copies merge once and unlock EX")
 ck(game.rules.get_player().gold==start_gold-3,"three one-gold purchases charge exact currency")
 var id:String=matches[0].id
 ck(game.command({"type":"deploy_unit","unit_id":id}).ok,"merged Asuna deploys")
 ck(game.place(id,Vector2(1.11,4.2)),"continuous non-grid player position accepted")
 for slot in [0,2]:
  var result:Dictionary=game.command({"type":"buy_offer","slot":slot})
  if result.ok:ck(game.command({"type":"deploy_unit","unit_id":result.unit_id}).ok,"available opening teammate deploys")
 var save:Dictionary=game.export_save();ck(save.get("ok",false),"activated preparation exports save")
 ck(game.command({"type":"start_battle"}).ok,"actual match starts with Asuna")
 var ex_count:=0;var movement:=0;var basic:=0
 for i in range(500):
  for event in game.advance(0.05):
   if event.get("character_id","")=="asuna":
    if event.type=="skill":ex_count+=1
    if event.type=="dash_move":movement+=1
    if event.type=="basic":basic+=1
  if game.phase()!="battle":break
 ck(ex_count>=1,"real merged recruit automatically casts EX without manual skill input")
 ck(movement>0,"real recruited Asuna follows legal dash movement")
 ck(game.clock.sim.units.all(func(u):return u.cell.is_finite()),"complete match uses finite positions")
 ck(game.rules.get_player().level==4 and game.rules.get_player().deployed.size()<=4,"initial population remains four")
 print("ASUNA LIVE SESSION CHECKS=",checks," FAILURES=",failures," ex=",ex_count," dash_steps=",movement," basic=",basic," phase=",game.phase())
 quit(1 if failures else 0)
