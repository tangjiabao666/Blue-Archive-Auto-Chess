extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func wait_for(condition:Callable,seconds:float=5.0)->bool:
 var end:int=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  if condition.call():return true
  await create_timer(0.02).timeout
 return condition.call()
func run():
 var script=load('res://scripts/lan/room_controller.gd');var nodes:Array=[]
 for i in range(3):
  var n=script.new();n.name='Room'+str(i);root.add_child(n);nodes.append(n)
 var h=nodes[0];var port:int=33000+int(Time.get_ticks_usec()%1000)
 h.create_room('127.0.0.1',port,'Host')
 for i in [1,2]:nodes[i].join_room('127.0.0.1',port,'Player'+str(i))
 ck(await wait_for(func():return h.human_count()==3),'three joined')
 ck(h.start_match(17).ok,'host starts')
 ck(await wait_for(func():return nodes.all(func(n):return not n.local_view.is_empty())),'private views delivered over JSON')
 for n in nodes:n.submit_command({'type':'buy_offer','slot':0})
 ck(await wait_for(func():return nodes.all(func(n):return n.local_view.player.units.size()==1)),'all independent shops authoritative')
 for n in nodes:n.submit_command({'type':'deploy_unit','unit_id':n.local_view.player.units[0].id})
 ck(await wait_for(func():return nodes.all(func(n):return n.local_view.player.deployed.size()==1)),'three armies deployed')
 for n in nodes:n.submit_command({'type':'ready','value':true})
 ck(await wait_for(func():return nodes.all(func(n):return n.local_view.phase=='loading')),'loading barrier broadcast')
 for n in nodes:n.mark_loaded()
 ck(await wait_for(func():return nodes.all(func(n):return n.local_view.phase=='battle' and n.local_view.battle.tick>=4)),'battle packets and ticks reach all peers')
 var gone:String=nodes[2].local_participant_id;nodes[2].leave_room()
 ck(await wait_for(func():return h.authority.rules.controllers[gone]=='ai'),'real ENet loss enables AI')
 ck(nodes[1].last_error.is_empty() and h.last_error.is_empty(),'remaining room stays valid')
 h.leave_room();ck(await wait_for(func():return nodes[1].last_error=='host_disconnected'),'host loss ends client')
 for n in nodes:n.queue_free()
 await process_frame;print('LAN_GAMEPLAY_NETWORK checks=',checks,' failures=',failures);quit(1 if failures else 0)
