extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func key(code:int)->InputEventKey:
 var e:=InputEventKey.new();e.keycode=code;e.pressed=true;return e
func mouse(button:int)->InputEventMouseButton:
 var e:=InputEventMouseButton.new();e.button_index=button;e.pressed=true;return e
func _initialize()->void:
 var path:='res://scripts/tactical_input.gd';ck(FileAccess.file_exists(path),'tactical input exists')
 if failures:finish();return
 var input=load(path).new();input.begin_battle(7,[10,11,-1,-1])
 var ctx:Dictionary={'phase':'battle','generation':7,'tick':10,'point':Vector2(1,2),'picked_actor':10,'units':[{'id':10,'team':0,'star':2,'hp':100,'cell':Vector2(0,2)},{'id':11,'team':0,'star':1,'hp':100,'cell':Vector2(1,2)},{'id':20,'team':1,'star':2,'hp':100,'cell':Vector2(0,-2)}],'target_modes':{10:'point',11:'self'}}
 var before:Dictionary=ctx.duplicate(true)
 ck(input.handle(key(KEY_1),ctx).is_empty() and input.armed_actor==10,'number key arms fixed slot')
 ck(input.handle(mouse(MOUSE_BUTTON_RIGHT),ctx).is_empty() and input.armed_actor==-1,'right click cancels targeting without movement')
 var commands:Array=input.handle(mouse(MOUSE_BUTTON_RIGHT),ctx)
 ck(commands.size()==1 and commands[0].type=='move' and commands[0].actor_id==10,'second right click moves selected actor')
 ck(input.handle(mouse(MOUSE_BUTTON_RIGHT),ctx).is_empty(),'pending click cannot double queue')
 input.acknowledge({'type':'command_rejected','team':0,'generation':7,'sequence':commands[0].sequence,'error':'blocked'})
 input.handle(key(KEY_2),ctx);ck(input.armed_actor==-1 and input.last_error=='ex_locked','one-star slot cannot arm')
 input.handle(key(KEY_1),ctx);commands=input.handle(mouse(MOUSE_BUTTON_LEFT),ctx)
 ck(commands.size()==1 and commands[0].type=='cast_ex' and commands[0].target_id==-1 and commands[0].point==ctx.point,'point skill confirms selected location')
 input.acknowledge({'type':'command_accepted','team':0,'generation':7,'sequence':commands[0].sequence})
 ck(input.armed_actor==-1 and not input.is_pending(),'accepted cast clears selection')
 ck(ctx==before,'targeting never mutates battle context or time')
 input.handle(key(KEY_1),ctx);input.handle(key(KEY_ESCAPE),ctx)
 ck(input.armed_actor==-1 and input.last_handled,'Escape cancels aim before menu')
 input.handle(key(KEY_ESCAPE),ctx);ck(not input.last_handled,'unarmed Escape remains available to menu')
 ctx.target_modes[10]='enemy';ctx.picked_actor=11
 input.handle(key(KEY_1),ctx);ck(input.handle(mouse(MOUSE_BUTTON_LEFT),ctx).is_empty() and input.last_error=='invalid_enemy_target','friendly click rejected for enemy skill')
 ctx.picked_actor=20;commands=input.handle(mouse(MOUSE_BUTTON_LEFT),ctx)
 ck(commands.size()==1 and commands[0].target_id==20,'enemy target bound to actual actor')
 input.begin_battle(8,[10,-1,-1,-1]);ctx.generation=8;ctx.target_modes[10]='self';input.handle(key(KEY_1),ctx)
 commands=input.handle(mouse(MOUSE_BUTTON_LEFT),ctx)
 ck(commands.size()==1 and commands[0].generation==8 and commands[0].target_id==10 and commands[0].point==ctx.units[0].cell,'self skill uses own location after restart')
 input.acknowledge({'type':'command_accepted','generation':7,'team':0,'sequence':commands[0].sequence});ck(input.is_pending(),'old generation acknowledgement cannot clear new action')
 ctx.units[0].hp=0;input.sync(ctx);ck(input.armed_actor==-1,'dead actor loses targeting')
 input.begin_battle(8,[10]);ctx.units[0].hp=100;ctx.generation=7
 ck(not input.arm_slot(0,ctx) and input.armed_actor==-1,'stale HUD cannot arm current actor')
 finish()
func finish()->void:
 print('TACTICAL_INPUT checks=',checks,' failures=',failures);quit(1 if failures else 0)
