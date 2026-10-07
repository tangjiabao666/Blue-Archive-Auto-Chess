extends SceneTree
var checks:=0
var failures:=0
func ck(value:bool,label:String):
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func _initialize():call_deferred("run")
func run():
 ck(ResourceLoader.exists("res://scripts/recruitment_preview_panel.gd"),"preview panel exists")
 if failures:quit(1);return
 var panel=load("res://scripts/recruitment_preview_panel.gd").new();root.add_child(panel)
 ck(not panel.visible,"starts hidden")
 var data={"ok":true,"character_id":"yuuka","name":"优香","cost":2,"role":"坦克","weapon":"SMG","attack_type":"爆发","armor_type":"重装甲","range":3.5,"stats_text":"一星生命 100\n二星生命 115","enhanced_text":"常驻防御提升","skills":[{"slot":"ex","label":"EX","name":"护盾","text":"二星解锁 · 自动释放","icon_key":"skill/COMMON_SKILLICON_SHIELD"},{"slot":"basic","label":"小技能","name":"射击","text":"定时射击","icon_key":"skill/COMMON_SKILLICON_TARGET"},{"slot":"sub","label":"子技能","name":"掩体","text":"进入掩体触发回复","icon_key":"skill/COMMON_SKILLICON_HEAL"}],"caveat":"系数不是最终伤害"}
 var before:Dictionary=data.duplicate(true)
 ck(panel.configure(data,null),"valid read-only preview accepted");panel.show()
 ck(panel.visible and panel.title_label.text.contains("优香"),"correct character shown")
 await process_frame;await process_frame
 ck(not panel.identity_label.get_rect().intersects(panel.stats_label.get_rect()),"identity and star stats do not overlap")
 ck(data==before,"presentation does not mutate model")
 ck(panel.close_button.has_focus(),"close receives focus")
 ck(panel.close_button.focus_next==panel.close_button.get_path_to(panel.scroll) and panel.scroll.focus_next==panel.scroll.get_path_to(panel.close_button),"modal focus cycle includes keyboard-readable content")
 var emitted:Array=[];panel.closed.connect(func():emitted.append(true))
 panel.close_panel();panel.close_panel()
 ck(not panel.visible and emitted.size()==1,"close emits once")
 ck(not panel.configure({"ok":false},null) and not panel.visible,"invalid data stays hidden")
 panel.configure(data,null);panel.show();data.skills[0].text="tampered"
 ck(not panel.skill_labels[0].text.contains("tampered"),"model copied into display")
 data.skills[0].text="很长的技能说明\n".repeat(50)
 panel.configure(data,null);panel.show();await process_frame;await process_frame
 panel.scroll.grab_focus()
 var down=InputEventKey.new();down.pressed=true;down.keycode=KEY_PAGEDOWN;panel._scroll_key_input(down)
 ck(panel.scroll.scroll_vertical>0,"keyboard can read overflowing skills")
 down.keycode=KEY_HOME;panel._scroll_key_input(down)
 ck(panel.scroll.scroll_vertical==0,"keyboard home returns to top")
 var sim=load("res://core/character_sim.gd").new()
 var session=load("res://core/game_session.gd").new()
 var presenter=load("res://core/recruitment_skill_presenter.gd")
 for key in session.ACTIVE:
  var model:Dictionary=presenter.describe(sim,key,session.profiles[key].display_name,int(session.COSTS[key]),5.0)
  panel.configure(model,null);await process_frame;await process_frame
  ck(not panel.identity_label.get_rect().intersects(panel.stats_label.get_rect()),key+" identity separation")
  ck(panel.stats_label.get_rect().end.y<=panel.caveat_label.position.y,key+" stats remain above footer")
  ck(panel.content.get_combined_minimum_size().x<=panel.scroll.size.x,key+" skills fit horizontal bounds")
 panel.free();print("RECRUITMENT_PREVIEW_PANEL ",checks," checks; ",failures," failures");quit(1 if failures else 0)
