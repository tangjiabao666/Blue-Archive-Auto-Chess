extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:call_deferred('run')
func run()->void:
 var path:='res://scripts/tactical_hud.gd';ck(FileAccess.file_exists(path),'tactical HUD exists')
 if failures:finish();return
 var hud=load(path).new();root.add_child(hud);await process_frame
 var slots:Array=[]
 for i in range(4):slots.append({'actor_id':10+i,'character_id':'serika','name':'芹香','cost':2,'star':2,'hp':100,'cooldown':0.0})
 var state:Dictionary={'active':true,'slots':slots,'energy':4,'moves':2,'energy_next':1.5,'move_next':0.0,'armed_actor':10,'pending':false,'hint':'选择落点'}
 hud.refresh(state);ck(hud.visible and hud.buttons.size()==6,'HUD creates six reusable fixed slots')
 ck(hud.energy_bar.value==4 and hud.energy_text.text.contains('4/10'),'shared energy shown')
 ck(hud.buttons[0].get_meta('actor_id')==10 and hud.buttons[0].icon!=null,'slot binds actual source icon')
 slots[1].hp=0;slots[2].star=1;state.slots=slots;hud.refresh(state)
 ck(hud.buttons[1].disabled and hud.buttons[1].get_meta('actor_id')==11,'dead slot disabled without reorder')
 ck(hud.buttons[2].disabled and hud.buttons[2].text.contains('二星'),'star gate visible')
 ck(not hud.buttons[4].visible,'unused capacity slots hidden')
 ck(hud.instructions.text.contains('1–4'),'instructions reflect actual fixed slots')
 var fg:Color=hud.buttons[2].get_theme_color('font_disabled_color');var bg:Color=hud.buttons[2].get_theme_stylebox('disabled').bg_color
 var visible_fg:Color=bg.lerp(fg,fg.a)
 var contrast:float=(maxf(visible_fg.srgb_to_linear().get_luminance(),bg.srgb_to_linear().get_luminance())+0.05)/(minf(visible_fg.srgb_to_linear().get_luminance(),bg.srgb_to_linear().get_luminance())+0.05)
 ck(contrast>=4.5,'locked or dead skill labels remain legible')
 await process_frame
 ck(hud.buttons.slice(0,4).all(func(b):return b.size.x<=150.01),'long localized labels never expand overlapping slots')
 state.active=false;hud.refresh(state);ck(not hud.visible,'HUD absent in preparation')
 hud.queue_free();await process_frame;finish()
func finish()->void:
 print('TACTICAL_HUD checks=',checks,' failures=',failures);quit(1 if failures else 0)
