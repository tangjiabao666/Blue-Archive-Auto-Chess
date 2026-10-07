extends SceneTree
var checks:int=0
var failures:int=0
var saved:int=0
var loaded:int=0
var closed:int=0
var applied:Dictionary={}
var quit_requests:int=0
func ck(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func run():
 ck(ResourceLoader.exists("res://scripts/game_menu.gd"),"game menu component exists")
 if failures:quit(1);return
 var menu=load("res://scripts/game_menu.gd").new();root.add_child(menu)
 ck(menu.has_signal("quit_requested"),"menu exposes an explicit quit action")
 ck(menu.get("reduce_smoke") is CheckBox,"menu exposes the optional smoke visibility checkbox")
 if failures:menu.free();quit(1);return
 menu.quit_requested.connect(func():quit_requests+=1)
 menu.save_requested.connect(func():saved+=1);menu.continue_requested.connect(func():loaded+=1);menu.closed.connect(func():closed+=1);menu.settings_requested.connect(func(values):applied=values)
 menu.open_menu({"volume":0.35,"muted":true,"fullscreen":false},false,true,"checkpoint note")
 ck(menu.visible and menu.mouse_filter==Control.MOUSE_FILTER_STOP,"menu blocks underlying input")
 ck(menu.save_button.disabled and not menu.continue_button.disabled,"phase and save availability reflected")
 ck(menu.read_preferences()=={"volume":0.35,"muted":true,"fullscreen":false,"reduce_smoke":false},"legacy settings shown exactly with original smoke default")
 ck(menu.reduce_smoke.text=="减弱烟雾遮挡","smoke mode label describes its visible effect")
 for text in ["仅影响画面","已识别的浓烟","Alpha","55%","默认关闭","不改变伤害"]:
  ck(menu.reduce_smoke.tooltip_text.contains(text),"smoke tooltip discloses %s"%text)
 ck(menu.reduce_smoke.focus_mode==Control.FOCUS_ALL,"smoke setting is keyboard focusable")
 ck(menu.fullscreen.find_next_valid_focus()==menu.reduce_smoke and menu.reduce_smoke.find_next_valid_focus()==menu.apply_button,"smoke checkbox follows settings before Apply in keyboard order")
 ck(menu.close_button.has_focus(),"opening menu preserves safe return-to-game focus")
 var panel:Control=menu.reduce_smoke.get_parent()
 var controls:Array=[menu.volume,menu.muted,menu.fullscreen,menu.reduce_smoke,menu.apply_button,menu.close_button,menu.save_button,menu.continue_button,menu.quit_button,menu.message]
 for first in range(controls.size()):
  ck(Rect2(Vector2.ZERO,panel.size).encloses(controls[first].get_rect()),"menu content remains inside panel")
  for second in range(first+1,controls.size()):ck(not controls[first].get_rect().intersects(controls[second].get_rect()),"menu controls do not overlap")
 menu.volume.value=70;menu.muted.button_pressed=false;menu.fullscreen.button_pressed=true;menu.reduce_smoke.button_pressed=true
 ck(applied.is_empty(),"editing preferences alone does not apply")
 menu.apply_button.pressed.emit();ck(applied=={"volume":0.7,"muted":false,"fullscreen":true,"reduce_smoke":true},"apply emits chosen values including smoke reduction")
 menu.reduce_smoke.button_pressed=false;menu.close_button.pressed.emit()
 ck(closed==1,"close delegates pause restoration")
 ck(applied.reduce_smoke,"closing does not apply a pending smoke change")
 menu.hide();menu.open_menu(applied,true,false,"new note")
 ck(menu.read_preferences()==applied,"reopening discards unapplied edits and retains applied smoke setting")
 ck(not menu.save_button.disabled and menu.continue_button.disabled,"reopening resets availability")
 menu.open_menu({"volume":1.0,"muted":false,"fullscreen":false},true,false,"legacy note")
 ck(menu.read_preferences().volume==1.0 and not menu.reduce_smoke.button_pressed,"legacy reopen restores default smoke instead of stale checkbox state")
 menu.save_button.pressed.emit();ck(saved==1,"save delegates storage")
 menu.continue_requested.emit();ck(loaded==1,"load delegates validation")
 menu.set_message("write failed",true);ck(menu.message.text=="write failed","failure visible")
 menu.quit_button.pressed.emit();ck(quit_requests==1,"quit delegates safe application exit")
 menu.free();print("GAME_MENU ",checks," checks; ",failures," failures");quit(1 if failures else 0)
