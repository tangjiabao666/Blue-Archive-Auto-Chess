extends SceneTree
var app
var clients:Array=[]
var next_action:=0
func _initialize():call_deferred('run')
func run():
 app=load('res://scripts/pc_app.gd').new();root.add_child(app);app._open_lan()
 while app.flow_state=='lan_loading':await process_frame
 if app.flow_state!='lan':quit(1);return
 app.lan_room.create_room('127.0.0.1',37831,'云端房主')
 for i in range(2):
  var room=load('res://scripts/lan/room_controller.gd').new();room.name='PreviewPeer'+str(i);root.add_child(room);clients.append(room);room.join_room('127.0.0.1',37831,'测试好友'+str(i+1))
 while app.lan_room.human_count()!=3:await process_frame
 app.lan_room.start_match(31)
 print('LAN_NATIVE_PREPARATION_READY')
func _process(_delta:float)->bool:
 if Time.get_ticks_msec()<next_action:return false
 next_action=Time.get_ticks_msec()+200
 for room in clients:
  if room.local_view.is_empty():continue
  var state:Dictionary=room.local_view;var p:Dictionary=state.player
  if state.phase=='preparation' and not state.ready[state.participant_id]:
   if p.reinforcement.get('status')=='pending':room.submit_command({'type':'claim_reinforcement','round':state.round,'slot':0})
   elif not p.bench.is_empty() and p.deployed.size()<p.level:room.submit_command({'type':'deploy_unit','unit_id':p.bench[0]})
   elif p.deployed.size()<p.level:
    var slot:=-1
    for i in range(p.shop.size()):
     if not p.shop[i].is_empty() and p.shop[i].cost<=p.gold:slot=i;break
    if slot>=0:room.submit_command({'type':'buy_offer','slot':slot})
    elif not p.deployed.is_empty():room.submit_command({'type':'ready','value':true})
   else:room.submit_command({'type':'ready','value':true})
  elif state.phase=='loading':room.mark_loaded()
  elif state.phase=='result':room.request_next()
 return false
