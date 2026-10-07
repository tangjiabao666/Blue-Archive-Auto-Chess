extends SceneTree
var checks:int=0
var failures:int=0
var applied:Array[Dictionary]=[]
var closed:int=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize():call_deferred("run")
func choose(button:OptionButton,index:int)->void:
 button.select(index);button.item_selected.emit(index)
func run():
 # Removing mobile opt-in, emitting during restore, or sharing preset state breaks this test.
 var menu=load("res://scripts/game_menu.gd").new();root.add_child(menu)
 ck(menu.has_method("configure_mobile"),"menu provides explicit mobile-only configuration")
 if failures:menu.free();finish();return
 menu.settings_requested.connect(func(values):applied.append(values))
 menu.closed.connect(func():closed+=1)
 var legacy:Dictionary={"volume":0.35,"muted":true,"fullscreen":true,"reduce_smoke":false}
 menu.open_menu(legacy,true,true,"Desktop note")
 ck(menu.read_preferences()==legacy,"unconfigured menu preserves exact four-field desktop preferences")
 var panel:Control=menu.reduce_smoke.get_parent()
 ck(panel.size==Vector2(580,536),"desktop panel keeps its existing dimensions")
 menu.configure_mobile(true)
 ck(menu.mobile_mode and not menu.fullscreen.visible,"mobile mode hides desktop fullscreen control")
 for key in ["quality_preset","render_scale","fps_limit"]:
  ck(menu.get(key) is OptionButton,"mobile provides %s option control"%key)
 if failures:menu.free();finish();return
 var preset:OptionButton=menu.quality_preset
 var resolution:OptionButton=menu.render_scale
 var fps:OptionButton=menu.fps_limit
 ck(preset.item_count==3 and resolution.item_count==4 and fps.item_count==4,"mobile exposes only supported quality, scale and FPS choices")
 for index in range(3):
  ck(preset.get_item_text(index)==["流畅","均衡","高清"][index],"quality options use clear Chinese labels")
  ck(preset.get_item_metadata(index)==["performance","balanced","high"][index],"quality labels retain stable setting values")
 for index in range(4):
  ck(resolution.get_item_metadata(index)==[0.5,0.67,0.85,1.0][index],"resolution offers exact supported independent values")
  ck(resolution.get_item_text(index).contains(["50%","67%","85%","100%"][index]),"resolution displays its percentage")
  ck(fps.get_item_metadata(index)==[30,60,90,120][index],"FPS offers supported independent caps")
 ck(resolution.tooltip_text.contains("3D") and resolution.tooltip_text.contains("UI"),"resolution explains that only 3D rendering changes")
 ck(fps.get_item_text(3).contains("上限") or fps.get_item_text(3).contains("目标"),"120 FPS is presented as a cap or target, never a guarantee")
 menu.open_menu(legacy,true,false,"Mobile note")
 var defaults:Dictionary=legacy.duplicate();defaults.merge({"quality_preset":"balanced","render_scale":0.85,"fps_limit":60})
 ck(menu.read_preferences()==defaults,"legacy settings open with balanced mobile defaults")
 ck(not menu.save_button.disabled and menu.continue_button.disabled,"mobile preserves save and continue availability")
 ck(menu.close_button.has_focus(),"mobile opening retains safe return focus")
 ck(applied.is_empty(),"mobile configuration and open never apply settings")
 ck(panel.size==Vector2(580,730),"mobile panel remains within 900 logical height")
 ck(panel.anchor_left==0.5 and panel.anchor_top==0.5 and panel.offset_left==-290 and panel.offset_top==-365,"mobile panel stays centered")
 var controls:Array=[menu.volume,menu.muted,menu.reduce_smoke,preset,resolution,fps,menu.apply_button,menu.close_button,menu.save_button,menu.continue_button,menu.quit_button]
 for control in controls:
  ck(control.size.y>=44,"every mobile input has at least 44 logical pixels of touch height")
 controls.append(menu.message)
 for first in range(controls.size()):
  ck(Rect2(Vector2.ZERO,panel.size).encloses(controls[first].get_rect()),"mobile content stays inside its panel")
  for second in range(first+1,controls.size()):
   ck(not controls[first].get_rect().intersects(controls[second].get_rect()),"mobile controls, actions and message do not overlap")
 var native_ui_size:Vector2=menu.size
 var old_max_fps:int=Engine.max_fps
 for index in range(3):
  menu.reduce_smoke.button_pressed=true
  choose(preset,index)
  var values:Dictionary=menu.read_preferences()
  ck(values.quality_preset==["performance","balanced","high"][index],"selecting preset updates its pending name")
  ck(values.render_scale==[0.67,0.85,1.0][index] and values.fps_limit==[60,60,120][index],"selecting preset fills recommended scale and FPS")
  ck(values.reduce_smoke,"preset selection keeps explicit smoke reduction manual")
  menu.reduce_smoke.button_pressed=false;choose(preset,index)
  ck(not menu.read_preferences().reduce_smoke,"preset selection never forces smoke reduction on")
 choose(resolution,0);choose(fps,2)
 var overridden:Dictionary=menu.read_preferences()
 ck(overridden.quality_preset=="high" and overridden.render_scale==0.5 and overridden.fps_limit==90,"manual scale and FPS override the selected preset independently")
 ck(menu.size==native_ui_size and Engine.max_fps==old_max_fps,"pending presentation controls cannot change UI size or global frame scheduling")
 ck(applied.is_empty(),"quality and individual control edits stay pending until Apply")
 menu.apply_button.pressed.emit()
 ck(applied.size()==1 and applied[0]==overridden,"Apply emits exactly the selected optional quality fields")
 choose(preset,0);menu.close_button.pressed.emit()
 ck(closed==1 and applied.size()==1,"cancel only requests close without applying pending quality edits")
 menu.hide();menu.open_menu(overridden,false,true,"Reopened note")
 ck(menu.read_preferences()==overridden,"reopening preserves explicit overrides instead of reapplying preset defaults")
 ck(applied.size()==1,"restoring explicit choices never emits Apply")
 ck(menu.save_button.disabled and not menu.continue_button.disabled,"reopening restores phase availability")
 ck(menu.message.text=="Reopened note","reopening restores message")
 menu.configure_mobile(true)
 ck(menu.read_preferences()==overridden,"repeated mobile configuration preserves pending explicit choices")
 choose(preset,1)
 ck(menu.read_preferences().render_scale==0.85 and menu.read_preferences().fps_limit==60,"the next preset selection intentionally replaces manual overrides")
 menu.open_menu(legacy,true,false,"Reset note")
 ck(menu.read_preferences()==defaults,"legacy reopen clears stale optional choices back to mobile defaults")
 menu.configure_mobile(false)
 ck(not menu.mobile_mode and menu.fullscreen.visible,"desktop reconfiguration restores fullscreen")
 ck(not preset.visible and not resolution.visible and not fps.visible,"desktop hides all mobile quality controls")
 ck(menu.read_preferences()==legacy and panel.size==Vector2(580,536),"desktop reconfiguration restores exact preference shape and layout")
 ck(menu.fullscreen.find_next_valid_focus()==menu.reduce_smoke and menu.reduce_smoke.find_next_valid_focus()==menu.apply_button,"hidden mobile controls do not alter desktop tab order")
 ck(applied.size()==1,"reconfiguration never applies settings")
 menu.free();finish()
func finish():
 print("MOBILE_QUALITY_MENU ",checks," checks; ",failures," failures");quit(1 if failures else 0)
