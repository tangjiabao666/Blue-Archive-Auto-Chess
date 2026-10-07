extends SceneTree
var checks:=0
var failures:=0
var claims:Array=[]
var skips:Array=[]
var closes:=0
func ck(value:bool,label:String):
 checks+=1
 if not value:failures+=1;printerr("FAIL ",label)
func _initialize():call_deferred("run")
func run():
 ck(ResourceLoader.exists("res://scripts/reinforcement_panel.gd"),"reinforcement chooser component exists")
 if failures:finish();return
 var panel=load("res://scripts/reinforcement_panel.gd").new();root.add_child(panel)
 panel.claim_requested.connect(func(r,s):claims.append([r,s]));panel.skip_requested.connect(func(r):skips.append(r));panel.closed.connect(func():closes+=1)
 var event:Dictionary={"round":3,"cost":2,"offers":["shiroko","yuuka","tsubaki"],"status":"pending","selected_slot":-1}
 var cards:Array=[]
 for key in event.offers:cards.append({"name":key,"portrait":null,"progress":"1/3 · 一星副本","description":"基础技能与被动保持原设定","can_claim":true})
 panel.configure(event,cards);panel.show()
 ck(panel.mouse_filter==Control.MOUSE_FILTER_STOP,"chooser blocks background mouse")
 ck(panel.claim_buttons.size()==3,"three distinct choice buttons")
 ck(panel.claim_buttons[0].tooltip_text.contains("基础技能"),"hoverable recruit button exposes skill details")
 ck(panel.close_button.has_focus(),"safe close focus on opening")
 ck(panel.title_label.text.contains("3") and panel.subtitle_label.text.contains("2"),"round and equal tier shown")
 event.round=6;cards[0].name="mutated"
 panel.claim_buttons[0].pressed.emit();panel.claim_buttons[0].pressed.emit()
 ck(claims==[[3,0]],"input copied and repeated activation emits only once")
 panel.hide();panel.claim_buttons[1].pressed.emit();ck(claims.size()==1,"hidden stale button cannot claim")
 event.round=3;cards[0].name="shiroko";cards[0].can_claim=false
 panel.configure(event,cards);panel.show()
 ck(panel.claim_buttons[0].disabled and not panel.claim_buttons[1].disabled,"full bench can disable only nonmerge claims")
 ck(panel.claim_buttons[0].text=="备战席已满" and panel.message.text.contains("上阵或出售"),"capacity blocker and recovery are visible without hover")
 panel.claim_buttons[0].pressed.emit();ck(claims.size()==1,"disabled programmatic activation cannot claim")
 panel.skip_button.pressed.emit();ck(skips.is_empty(),"skip first asks explicitly")
 ck(panel.confirm_skip_button.visible and panel.cancel_skip_button.visible,"skip confirmation shown inline")
 ck(panel.claim_buttons[1].disabled,"claims inert during skip confirmation")
 panel.cancel_skip_button.pressed.emit();ck(skips.is_empty() and not panel.claim_buttons[1].disabled,"cancel restores choices without mutation")
 panel.skip_button.pressed.emit();panel.confirm_skip_button.pressed.emit();panel.confirm_skip_button.pressed.emit();ck(skips==[3],"confirmed skip emits once with frozen round")
 panel.configure(event,cards);panel.show();panel.close_button.pressed.emit();ck(closes==1 and not panel.visible and skips==[3],"close postpones without skipping")
 panel.configure(event,cards);panel.show();panel.skip_button.pressed.emit();panel.close_panel();ck(closes==2 and not panel.visible,"close during confirmation remains nonmutating")
 panel.configure(event,cards);panel.show();ck(not panel.confirm_skip_button.visible,"reopen resets confirmation state")
 panel.set_message("备战席已满",true);ck(panel.message.text=="备战席已满","failure visible inside chooser")
 var focus:Control=panel.close_button
 for i in range(15):
  focus=focus.find_next_valid_focus();ck(panel.is_ancestor_of(focus),"tab cycle stays in chooser")
 panel.configure({},[]);ck(not panel.visible,"invalid or resolved event closes chooser")
 panel.free();finish()
func finish():print("REINFORCEMENT PANEL ",checks," checks; ",failures," failures");quit(1 if failures else 0)
