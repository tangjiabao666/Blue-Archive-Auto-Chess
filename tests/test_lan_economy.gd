extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 ck(ResourceLoader.exists('res://core/lan/room_rules.gd'),'room rules exist')
 if failures:quit(1);return
 var rules=load('res://core/lan/room_rules.gd').new();ck(rules.new_match(23,['p0','p1','p2']).ok,'three-human match begins')
 for id in ['p0','p1','p2']:ck(rules.get_player(id).gold==10 and rules.get_player(id).units.is_empty(),'AI does not purchase for '+id)
 ck(not rules.get_player('p3').units.is_empty(),'real AI still prepares')
 var host:Dictionary=rules.get_player('p0');var before:Dictionary=rules.snapshot();var cost:int=rules.get_player('p1').shop[0].cost
 var bought:Dictionary=rules.execute_for('p1',{'type':'buy_offer','slot':0})
 ck(bought.ok and rules.get_player('p1').gold==10-cost,'client purchase spends own gold')
 ck(rules.get_player('p0')==host,'client purchase cannot alter host')
 var after:Dictionary=rules.snapshot();ck(not rules.execute_for('p1',{'type':'buy_offer','slot':0}).ok and rules.snapshot()==after,'duplicate slot purchase is atomic rejection')
 ck(not rules.execute_for('p2',{'type':'deploy_unit','unit_id':bought.unit_id}).ok,'cannot deploy another player unit')
 ck(rules.execute_for('p1',{'type':'deploy_unit','unit_id':bought.unit_id}).ok,'owner can deploy')
 ck(rules.set_ready('p1',true).ok,'player can lock ready')
 after=rules.snapshot();ck(not rules.execute_for('p1',{'type':'refresh_shop'}).ok and rules.snapshot()==after,'ready blocks changes')
 ck(rules.set_ready('p1',false).ok and rules.execute_for('p1',{'type':'sell_unit','unit_id':bought.unit_id}).ok,'cancel ready permits own sell')
 ck(rules.player_view('p1').positions.is_empty(),'sell removes stale placement')
 ck(not rules.execute_for('p1',{'type':'resolve_battle','winner':'player'}).ok,'client cannot resolve match')
 ck(not rules.player_view('p1').has('players'),'private view does not expose all private economies')
 print('LAN_ECONOMY checks=',checks,' failures=',failures);quit(1 if failures else 0)
