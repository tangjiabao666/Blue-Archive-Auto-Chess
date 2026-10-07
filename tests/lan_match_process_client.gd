extends SceneTree
var room
var role:String
var directory:String
var deadline:int
var sent_ready:=-1
var loaded:=-1
var continued:=-1
var seen_rounds:Array=[]
var saw_team1:=false
var max_bytes:=0
var next_action:=0
var final_seen:=false
var drop_mode:=false
func _initialize():call_deferred('run')
func run():
 var args:PackedStringArray=OS.get_cmdline_user_args();role=args[0];directory=args[2];drop_mode=args.size()>3 and args[3]=='drop';deadline=Time.get_ticks_msec()+150000
 room=load('res://scripts/lan/room_controller.gd').new();room.name='Room';root.add_child(room)
 var result:Dictionary=room.create_room('127.0.0.1',int(args[1]),'Host') if role=='host' else room.join_room('127.0.0.1',int(args[1]),role)
 if not result.ok:finish(false,'connect');return
 while Time.get_ticks_msec()<deadline:
  if not room.last_error.is_empty():finish(false,room.last_error);return
  if role=='host' and room.phase=='lobby' and room.human_count()==3:room.start_match(31)
  if not room.local_view.is_empty():
   var state:Dictionary=room.local_view
   max_bytes=maxi(max_bytes,JSON.stringify(load('res://core/lan/view_codec.gd').pack(state)).to_utf8_buffer().size())
   if state.round not in seen_rounds:seen_rounds.append(state.round)
   if state.has('battle') and state.battle.right_id==state.participant_id:saw_team1=true
   if state.phase=='preparation' and Time.get_ticks_msec()>=next_action:
    next_action=Time.get_ticks_msec()+80
    var p:Dictionary=state.player
    if p.reinforcement.get('status')=='pending':room.submit_command({'type':'claim_reinforcement','round':state.round,'slot':0})
    elif not p.bench.is_empty() and p.deployed.size()<p.level:room.submit_command({'type':'deploy_unit','unit_id':p.bench[0]})
    elif p.deployed.size()<p.level:
     var slot:=-1
     for i in range(p.shop.size()):
      if not p.shop[i].is_empty() and p.shop[i].cost<=p.gold:slot=i;break
     if slot>=0:room.submit_command({'type':'buy_offer','slot':slot})
     elif not p.deployed.is_empty() and sent_ready!=state.round:sent_ready=state.round;room.submit_command({'type':'ready','value':true})
    elif sent_ready!=state.round:sent_ready=state.round;room.submit_command({'type':'ready','value':true})
   elif state.phase=='loading' and loaded!=state.round:loaded=state.round;room.mark_loaded()
   elif state.phase=='battle':
    if drop_mode and role!='host' and state.round==(1 if role=='a' else 2) and state.battle.tick>=20:finish(true,'intentional_client_drop');return
    if role=='host':room.authority.advance(0.5)
   elif state.phase=='result' and continued!=state.round:
    continued=state.round;room.request_next()
   elif state.phase=='finished':
    finish(true,'finished');return
  await create_timer(0.02).timeout
 finish(false,'deadline')
func finish(ok:bool,reason:String):
 var view:Dictionary=room.local_view.duplicate(true)
 var file=FileAccess.open(directory+'/'+role+'.json',FileAccess.WRITE)
 file.store_string(JSON.stringify({'ok':ok,'reason':reason,'pid':OS.get_process_id(),'role':role,'participant':room.local_participant_id,'rounds':seen_rounds,'team1':saw_team1,'max_bytes':max_bytes,'standings':view.get('standings',[]),'last_result':view.get('last_result',{}),'controllers':view.get('controllers',{}),'error':room.last_error}));file.close()
 if role=='host' and ok:
  for i in range(250):
   if FileAccess.file_exists(directory+'/a.json') and FileAccess.file_exists(directory+'/b.json'):break
   await create_timer(0.02).timeout
 elif reason=='finished':
  for i in range(100):
   if room.phase=='idle':break
   await create_timer(0.02).timeout
 room.leave_room();room.queue_free();await process_frame;quit(0 if ok else 1)
