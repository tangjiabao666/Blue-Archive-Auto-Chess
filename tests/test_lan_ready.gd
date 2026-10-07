extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 ck(ResourceLoader.exists('res://core/lan/room_rules.gd'),'room rules exist')
 if failures:quit(1);return
 var r=load('res://core/lan/room_rules.gd').new();r.new_match(7,['p0','p1','p2'])
 ck(not r.set_ready('p0',true).ok,'empty human army cannot ready')
 for id in ['p0','p1','p2']:
  var bought:Dictionary=r.execute_for(id,{'type':'buy_offer','slot':0});r.execute_for(id,{'type':'deploy_unit','unit_id':bought.unit_id})
  var before:Dictionary=r.snapshot();ck(not r.execute_for(id,{'type':'place_unit','unit_id':bought.unit_id,'point':Vector2(NAN,1)}).ok and r.snapshot()==before,'invalid placement leaves state untouched')
  r.set_ready(id,true)
  if id!='p2':ck(not r.freeze_round().ok,'no premature freeze before all three')
 ck(r.set_ready('p1',false).ok and not r.freeze_round().ok,'cancel last-moment ready stops freeze')
 r.set_ready('p1',true);var frozen:Dictionary=r.freeze_round()
 ck(frozen.ok and frozen.pairs.size()==4 and frozen.armies.size()==8,'all eight participants frozen in four pairs')
 ck(r.snapshot().phase=='loading' and not r.freeze_round().ok,'freeze once and wait for loading')
 print('LAN_READY checks=',checks,' failures=',failures);quit(1 if failures else 0)
