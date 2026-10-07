extends RefCounted
var selected_actor:=-1
var armed_actor:=-1
var last_handled:=false
var last_error:=''
var _generation:=-1
var _slots:Array=[]
var _sequence:=0
var _pending_sequence:=-1
func begin_battle(generation:int,slots:Array)->void:
 _generation=generation;_slots=slots.duplicate();_sequence=0;_pending_sequence=-1
 selected_actor=-1;armed_actor=-1;last_error='';last_handled=false
func cancel()->void:armed_actor=-1;last_error=''
func is_pending()->bool:return _pending_sequence>=0
func slots()->Array:return _slots.duplicate()
func sync(context:Dictionary)->void:
 if context.get('generation',-1)!=_generation or context.get('phase','')!='battle':
  armed_actor=-1;selected_actor=-1;return
 if not _alive(_actor(context,selected_actor)):selected_actor=-1
 if not _alive(_actor(context,armed_actor)):armed_actor=-1
func arm_slot(index:int,context:Dictionary)->bool:
 sync(context)
 if context.get("generation",-1)!=_generation or context.get("phase","")!="battle":return false
 if is_pending() or index<0 or index>=_slots.size():return false
 var actor:Dictionary=_actor(context,_slots[index])
 if not _alive(actor):last_error='actor_dead';return false
 if actor.team!=0:return false
 if actor.star!=2:last_error='ex_locked';return false
 selected_actor=actor.id;armed_actor=actor.id;last_error='';return true
func handle(event:InputEvent,context:Dictionary)->Array:
 last_handled=false;sync(context)
 if context.get('phase','')!='battle' or context.get('generation',-1)!=_generation:return []
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode==KEY_ESCAPE and armed_actor>=0:
   cancel();last_handled=true;return []
  if event.keycode>=KEY_1 and event.keycode<=KEY_6:
   last_handled=true;arm_slot(event.keycode-KEY_1,context);return []
 if not event is InputEventMouseButton or not event.pressed:return []
 if event.button_index==MOUSE_BUTTON_RIGHT and armed_actor>=0:
  cancel();last_handled=true;return []
 if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:return []
 if is_pending():last_handled=true;return []
 if event.button_index==MOUSE_BUTTON_LEFT:
  if armed_actor>=0:return _confirm_ex(context)
  var picked:Dictionary=_actor(context,int(context.get('picked_actor',-1)))
  if _alive(picked) and picked.team==0:selected_actor=picked.id;last_error='';last_handled=true
  return []
 if selected_actor>=0:
  last_handled=true
  if not context.get('point') is Vector2 or not context.point.is_finite():last_error='invalid_destination';return []
  return [_command('move',selected_actor,-1,context.point)]
 return []
func _confirm_ex(context:Dictionary)->Array:
 last_handled=true
 var actor:Dictionary=_actor(context,armed_actor)
 if not _alive(actor):cancel();last_error='actor_dead';return []
 var mode:String=context.get('target_modes',{}).get(armed_actor,'point')
 var target_id:=-1;var point:Vector2
 if mode=='self':target_id=actor.id;point=actor.cell
 elif mode=='enemy':
  var target:Dictionary=_actor(context,int(context.get('picked_actor',-1)))
  if not _alive(target) or target.team==actor.team:last_error='invalid_enemy_target';return []
  target_id=target.id;point=target.cell
 else:
  if not context.get('point') is Vector2 or not context.point.is_finite():last_error='invalid_destination';return []
  point=context.point
 return [_command('cast_ex',armed_actor,target_id,point)]
func _command(kind:String,actor:int,target:int,point:Vector2)->Dictionary:
 _sequence+=1;_pending_sequence=_sequence;last_error=''
 return {'type':kind,'actor_id':actor,'target_id':target,'point':point,'sequence':_sequence,'generation':_generation}
func acknowledge(event:Dictionary)->void:
 if event.get('generation',-1)!=_generation or event.get('team',-1)!=0 or event.get('sequence',-1)!=_pending_sequence:return
 if event.get('type','') not in ['command_accepted','command_rejected']:return
 _pending_sequence=-1
 if event.type=='command_accepted':armed_actor=-1;last_error=''
 else:last_error=str(event.get('error','invalid_command'))
func _actor(context:Dictionary,id:int)->Dictionary:
 for actor in context.get('units',[]):
  if actor.id==id:return actor
 return {}
func _alive(actor:Dictionary)->bool:return not actor.is_empty() and actor.get('hp',0)>0
