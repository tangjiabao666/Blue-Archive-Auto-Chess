extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func wait_for(condition:Callable,seconds:float=4.0)->bool:
 var end:int=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  if condition.call():return true
  await create_timer(0.02).timeout
 return condition.call()
func run():
 ck(ResourceLoader.exists('res://scripts/lan/room_controller.gd'),'LAN room controller exists')
 if failures:quit(1);return
 var script=load('res://scripts/lan/room_controller.gd');var nodes:Array=[]
 for i in range(4):
  var node=script.new();node.name='Room'+str(i);root.add_child(node);nodes.append(node)
 var host=nodes[0];var a=nodes[1];var b=nodes[2];var extra=nodes[3];var port:int=29000+int(Time.get_ticks_usec()%1000)
 ck(host.create_room('127.0.0.1',port,'房主').ok,'loopback host binds')
 ck(a.join_room('127.0.0.1',port,'甲').ok and b.join_room('127.0.0.1',port,'乙').ok,'two clients initiate real connections')
 ck(await wait_for(func():return host.human_count()==3 and a.phase=='lobby' and b.phase=='lobby'),'three peers complete handshake')
 ck(a.snapshot()==host.snapshot() and b.snapshot()==host.snapshot(),'all peers share canonical room state')
 ck(a.local_participant_id!=b.local_participant_id and a.local_participant_id!='p0','each client gets distinct nonhost seat')
 extra.join_room('127.0.0.1',port,'多余')
 ck(await wait_for(func():return not extra.last_error.is_empty()),'fourth player rejected')
 ck(host.human_count()==3,'extra connection cannot replace existing participant')
 var old_epoch:int=host.snapshot().epoch
 a.leave_room();ck(await wait_for(func():return host.human_count()==2),'lobby disconnect releases seat')
 extra.leave_room();extra.build_id='incompatible';extra.join_room('127.0.0.1',port,'错版本')
 ck(await wait_for(func():return extra.last_error=='version_mismatch'),'different build rejected')
 b.leave_room();host.leave_room();await process_frame
 ck(host.create_room('127.0.0.1',port,'新房').ok and host.snapshot().epoch!=old_epoch,'same port reopens with new room epoch')
 for node in nodes:node.leave_room();node.queue_free()
 await process_frame;print('LAN_ROOM checks=',checks,' failures=',failures);quit(1 if failures else 0)
