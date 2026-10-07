extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 ck(ResourceLoader.exists('res://scripts/round_result_panel.gd'),'round result presenter exists')
 if failures:quit(1);return
 var panel=load('res://scripts/round_result_panel.gd').new();root.add_child(panel)
 var state:Dictionary={'phase':'result','last_result':{'round':2,'winner':'player','combat':{'duration_ticks':1800,'finish_reason':'timeout','remaining_hp_totals':[40000,20000]}},'players':[{'id':'p0','name':'你'},{'id':'p1','name':'对手'}],'standings':[{'participant_id':'p0','rank':1,'points':4},{'participant_id':'p1','rank':2,'points':0}]}
 panel.present(state,{})
 ck(panel.heading.text.contains('胜利') and panel.summary.text.contains('+2'),'winner and score delta shown')
 ck(panel.summary.text.contains('40000') and panel.summary.text.contains('20000'),'timeout total health explanation shown')
 ck(panel.next_button.visible and not panel.new_button.visible,'nonfinal offers next round')
 var clicks:Array=[];panel.next_round_requested.connect(func():clicks.append(1));panel.next_button.pressed.emit();panel.next_button.pressed.emit()
 ck(clicks.size()==1,'double click emits only one progression')
 state.phase='finished';state.last_result.round=6;state.placement=1;panel.present(state,{})
 ck(not panel.next_button.visible and panel.new_button.visible and panel.title_button.visible,'final offers restart and title')
 ck(panel.heading.text.contains('第 1 名') and panel.ranking.text.contains('4 分'),'final actual standings shown')
 for outcome in ['opponent','draw']:
  state.phase='result';state.last_result.winner=outcome;panel.present(state,{})
  ck(panel.heading.text.contains('失败' if outcome=='opponent' else '平局'),'nonwinning outcome shown')
 panel.queue_free();await process_frame;print('PC_ROUND_RESULTS checks=',checks,' failures=',failures);quit(1 if failures else 0)
