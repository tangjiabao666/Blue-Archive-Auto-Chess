extends SceneTree
var failures:=0
func check(value:bool,label:String)->void:
 if not value:failures+=1;printerr(label)
func _initialize():call_deferred('run')
func run():
 var presenter=load('res://core/combat_status_presenter.gd').new()
 var strip=load('res://scripts/combat_status_strip.gd').new();root.add_child(strip)
 var unit:Dictionary={'hp':100,'star':1,'cover_status':{'state':'protected','threat_id':7,'multiplier':0.7,'direction':Vector2.UP}}
 var state:Dictionary=presenter.present(unit,0,{})
 var covers:Array=state.effects.filter(func(e):return e.id=='terrain_cover')
 check(covers.size()==1,'protected cover has visible badge')
 if covers.size():check(covers[0].hint.contains('30%') and covers[0].hint.contains('抛射'),'directional tooltip explains damage and exceptions')
 strip.update_unit(unit,0,{})
 unit.cover_status.state='exposed';unit.cover_status.multiplier=1.0
 strip.update_unit(unit,0,{})
 check(strip.tooltip_text.contains('暴露'),'same-tick cover transition refreshes cache')
 check(not strip.tooltip_text.contains('减伤 30%'),'old protection tooltip removed')
 unit.cover_status.state='none';strip.update_unit(unit,0,{})
 check(strip.status.effects.filter(func(e):return e.id=='terrain_cover').is_empty(),'leaving cover removes badge')
 unit.cover_status.state='protected'
 check(presenter.present(unit,0,{},true).effects.is_empty(),'preparation hides stale combat cover')
 strip.queue_free();await process_frame
 print('COVER UI FAILURES=',failures);quit(1 if failures else 0)
