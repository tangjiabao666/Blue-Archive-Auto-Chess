extends SceneTree
func _initialize():call_deferred('run')
func wait_for(condition:Callable,seconds:float=4.0)->bool:
 var end:int=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  if condition.call():return true
  await create_timer(0.01).timeout
 return condition.call()
func run():
 var script=load('res://scripts/lan/room_controller.gd');var nodes:Array=[]
 for i in range(3):
  var n=script.new();n.name='ReviewRoom'+str(i);root.add_child(n);nodes.append(n)
 var h=nodes[0];var port:int=39000+int(Time.get_ticks_usec()%1000);h.create_room('127.0.0.1',port,'Host')
 for i in [1,2]:nodes[i].join_room('127.0.0.1',port,'Player'+str(i))
 if not await wait_for(func():return h.human_count()==3):printerr('JOIN FAILED');quit(2);return
 h.start_match(17)
 if not await wait_for(func():return nodes.all(func(n):return not n.local_view.is_empty())):printerr('START FAILED');quit(2);return
 await create_timer(1.15).timeout
 print('BEFORE a_budget=',h.wire._budgets,' b_budget=',nodes[2].wire._budgets)
 for i in range(119):nodes[1].submit_command({'type':'ready','value':false})
 await create_timer(1.5).timeout
 print('AFTER host_error=',h.last_error,' a_error=',nodes[1].last_error,' b_error=',nodes[2].last_error,' controllers=',h.authority.rules.controllers if h.authority!=null else {},' b_budget=',nodes[2].wire._budgets)
 var ok:bool=nodes[2].last_error.is_empty() and nodes[2].phase=='preparation' and h.human_count()==3
 for n in nodes:n.leave_room();n.queue_free()
 await process_frame;print('LAN_NOISY_PEER ', 'PASS' if ok else 'FAIL');quit(0 if ok else 1)
