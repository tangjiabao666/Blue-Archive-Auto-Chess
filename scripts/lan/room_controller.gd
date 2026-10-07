extends Node
const Protocol=preload('res://core/lan/protocol.gd')
const Authority=preload('res://core/lan/authority.gd')
const Codec=preload('res://core/lan/view_codec.gd')
signal view_received(view:Dictionary)
signal command_ack(result:Dictionary)
var authority
var local_view:Dictionary={}
var _request_sequence:=0
var _publish_elapsed:=0.0
var _event_cursors:Dictionary={}
var _loading_at:=0
const Transport=preload('res://scripts/lan/transport.gd')
signal changed(state:Dictionary)
signal room_closed(reason:String)
signal participant_left(participant_id:String)
signal intent_received(participant_id:String,request:Dictionary)
var build_id:String=Protocol.BUILD_ID
var phase:String='idle'
var last_error:String=''
var local_participant_id:String=''
var is_host:=false
var wire:Node
var _state:Dictionary={}
var _peers:Dictionary={}
var _last_received:Dictionary={}
var _pending:Dictionary={}
var _seen_seq:Dictionary={}
var _seq:=0
var _nickname:String=''
var _started_at:=0
var _heartbeat_at:=0
func _ready()->void:
 wire=Transport.new();wire.name='Wire';add_child(wire)
 wire.message_received.connect(_receive)
 wire.connected.connect(_connected)
 wire.peer_joined.connect(func(id):
  if is_host:_pending[id]=Time.get_ticks_msec())
 wire.peer_left.connect(_disconnected)
 wire.failed.connect(_failed)
func create_room(bind_ip:String,port:int,nickname:String)->Dictionary:
 leave_room();last_error=''
 if not _valid_name(nickname):return _failure('invalid_nickname')
 var error:Error=wire.host(bind_ip,port)
 if error!=OK:return _failure('host_failed:'+str(error))
 is_host=true;phase='lobby';local_participant_id='p0';_nickname=nickname
 var seats:Array=[]
 for i in range(8):seats.append({'id':'p'+str(i),'peer':1 if i==0 else 0,'name':nickname if i==0 else 'AI '+str(i) if i>=3 else '等待加入','controller':'human' if i==0 else 'ai' if i>=3 else 'empty','ready':false})
 _state={'epoch':int(Time.get_ticks_usec())+randi_range(1,1000000),'revision':0,'phase':'lobby','seats':seats}
 _peers={1:'p0'};_emit_state();return {'ok':true}
func join_room(ip:String,port:int,nickname:String)->Dictionary:
 leave_room();last_error=''
 if not _valid_name(nickname):return _failure('invalid_nickname')
 var error:Error=wire.join(ip,port)
 if error!=OK:return _failure('join_failed:'+str(error))
 phase='joining';_nickname=nickname;_started_at=Time.get_ticks_msec();return {'ok':true}
func leave_room()->void:
 if authority!=null:authority.close();authority=null
 local_view.clear();_event_cursors.clear();_request_sequence=0
 if wire!=null:wire.close()
 phase='idle';is_host=false;local_participant_id='';_state.clear();_peers.clear();_pending.clear();_last_received.clear();_seen_seq.clear();_seq=0
func snapshot()->Dictionary:return _state.duplicate(true)
func human_count()->int:
 var count:=0
 for seat in _state.get('seats',[]):
  if seat.controller=='human':count+=1
 return count
func _connected()->void:
 _send(1,'hello',{'build':build_id,'nickname':_nickname})
func _send(peer_id:int,type:String,payload:Dictionary)->void:
 _seq+=1
 wire.send_to(peer_id,{'protocol':Protocol.VERSION,'type':type,'epoch':_state.get('epoch',0),'seq':_seq,'payload':payload})
func _receive(sender:int,message:Dictionary)->void:
 var now:int=Time.get_ticks_msec()
 if is_host:
  if message.type=='hello':_hello(sender,message);return
  if not _peers.has(sender) or message.epoch!=_state.epoch:return
  if message.seq<=int(_seen_seq.get(sender,-1)):return
  _seen_seq[sender]=message.seq;_last_received[sender]=now
  if message.type=='ping':_send(sender,'pong',{});return
  if message.type=='intent':
   intent_received.emit(_peers[sender],message.payload)
   if authority!=null:
    var ack:Dictionary=authority.submit_intent(_peers[sender],Codec.unpack(message.payload));_send(sender,'ack',Codec.pack(ack)) # Scheduled10Hz publish coalesces client intents.
   return
  if authority!=null and message.type in ['loaded','next']:
   if message.payload.get('round')!=authority.rules._state.round:return
   if message.type=='loaded':authority.mark_loaded(_peers[sender])
   else:authority.request_next(_peers[sender])
   _publish_views();return
  return
 if sender!=1:return
 if message.type=='error':_failed(str(message.payload.get('reason','server_error')));return
 if message.type=='welcome' and phase=='joining':
  var state:Variant=message.payload.get('state');var you:Variant=message.payload.get('you')
  if not _valid_state(state) or you not in ['p1','p2']:_failed('invalid_welcome');return
  _state=state;local_participant_id=you;phase=state.phase;_seen_seq[1]=message.seq;_last_received[1]=now;_emit_state();return
 var sequence_key:Variant='view' if message.type=='view' else 1
 if _state.is_empty() or message.epoch!=_state.epoch or message.seq<=int(_seen_seq.get(sequence_key,-1)):return
 _seen_seq[sequence_key]=message.seq;_last_received[1]=now
 if message.type=='view':
  local_view=Codec.unpack(message.payload);view_received.emit(local_view.duplicate(true));return
 if message.type=='ack':command_ack.emit(Codec.unpack(message.payload));return
 if message.type=='room_state':
  if not _valid_state(message.payload) or message.payload.epoch!=_state.epoch:return
  if message.payload.revision<_state.revision:return
  var previous_phase:String=phase
  _state=message.payload;phase=_state.phase
  if phase=='loading' and previous_phase!='loading':_loading_at=now
  _emit_state()
func _hello(sender:int,message:Dictionary)->void:
 if _peers.has(sender):return
 var payload:Dictionary=message.payload
 if payload.size()!=2 or not payload.get('build') is String or payload.build!=build_id:_reject(sender,'version_mismatch');return
 if not _valid_name(payload.get('nickname')):_reject(sender,'invalid_nickname');return
 if phase!='lobby':_reject(sender,'match_in_progress');return
 var index:=-1
 for i in [1,2]:
  if _state.seats[i].controller=='empty':index=i;break
 if index<0:_reject(sender,'room_full');return
 _state.seats[index]={'id':'p'+str(index),'peer':sender,'name':payload.nickname,'controller':'human','ready':false}
 _peers[sender]='p'+str(index);_pending.erase(sender);_last_received[sender]=Time.get_ticks_msec();_seen_seq[sender]=message.seq
 _state.revision+=1;_send(sender,'welcome',{'you':'p'+str(index),'state':_state});_broadcast_state()
func _reject(sender:int,reason:String)->void:
 # Deliver the reliable reason before the client closes its connection.
 # Uncooperative rejected peers remain under the handshake timeout.
 _send(sender,'error',{'reason':reason})
 if not _pending.has(sender):_pending[sender]=Time.get_ticks_msec()
func _disconnected(peer_id:int)->void:
 if is_host:
  _pending.erase(peer_id);_last_received.erase(peer_id);_seen_seq.erase(peer_id)
  if not _peers.has(peer_id):return
  var participant:String=_peers[peer_id];_peers.erase(peer_id)
  var index:int=int(participant.trim_prefix('p'))
  if phase=='lobby':_state.seats[index]={'id':participant,'peer':0,'name':'等待加入','controller':'empty','ready':false}
  else:
   _state.seats[index].peer=0;_state.seats[index].controller='ai';participant_left.emit(participant)
   if authority!=null:authority.take_over(participant)
  _state.revision+=1;_broadcast_state()
 elif peer_id==1 and phase!='idle':_failed('host_disconnected')
func _broadcast_state()->void:
 for id in _peers:
  if id!=1:_send(id,'room_state',_state)
 _emit_state()
func _emit_state()->void:changed.emit(snapshot())
func _failed(reason:String)->void:
 if not last_error.is_empty():return
 leave_room();last_error=reason;room_closed.emit(reason)
func _failure(reason:String)->Dictionary:
 last_error=reason;return {'ok':false,'error':reason}
func _process(_delta:float)->void:
 if is_host and authority!=null:
  authority.advance(_delta);_publish_elapsed+=_delta
  if _publish_elapsed>=0.1:_publish_elapsed=0.0;_publish_views()
  if not authority.last_error.is_empty():_end_match('simulation_error');return
 var now:int=Time.get_ticks_msec()
 if phase=='joining' and now-_started_at>10000:_failed('handshake_timeout');return
 if phase=='idle':return
 if is_host:
  for id in _pending.keys():
   if now-int(_pending[id])>10000:wire.disconnect_peer(id);_pending.erase(id)
  if phase=='loading' and _loading_expired(now):
   for id in _peers.keys():
    if id!=1 and not authority._loaded.get(_peers[id],false):wire.disconnect_peer(id);_disconnected(id)
   if not authority._loaded.get('p0',false):_end_match('host_loading_timeout');return
  if phase!='loading':
   for id in _last_received.keys():
    if now-int(_last_received[id])>15000:wire.disconnect_peer(id);_disconnected(id)
 elif phase=='loading' and _loading_expired(now):_failed('loading_timeout');return
 elif phase!='joining' and phase!='loading' and now-int(_last_received.get(1,now))>15000:_failed('host_timeout');return
 if now-_heartbeat_at>=1000 and not is_host and phase not in ['idle','joining']:_heartbeat_at=now;_send(1,'ping',{})
func _valid_name(value:Variant)->bool:
 if not value is String or value.strip_edges().is_empty() or value.length()>24:return false
 for index in range(value.length()):
  if value.unicode_at(index)<32:return false
 return not value.contains('\n') and not value.contains('\r') and not value.contains('\t')
func _valid_state(value:Variant)->bool:
 if not value is Dictionary or value.size()!=4:return false
 if not Protocol.whole(value.get('epoch')) or not Protocol.whole(value.get('revision')) or value.get('phase') not in ['lobby','preparation','loading','battle','result','finished']:return false
 if not value.get('seats') is Array or value.seats.size()!=8:return false
 for i in range(8):
  var seat:Variant=value.seats[i]
  if not seat is Dictionary or seat.size()!=5 or not seat.get('id') is String or seat.id!='p'+str(i) or not Protocol.whole(seat.get('peer')) or not _valid_name(seat.get('name')) or seat.get('controller') not in ['human','ai','empty'] or not seat.get('ready') is bool:return false
 value.epoch=int(value.epoch);value.revision=int(value.revision)
 for seat in value.seats:seat.peer=int(seat.peer)
 return true
func _exit_tree()->void:leave_room()

func start_match(seed_value:int=1)->Dictionary:
 if not is_host or phase!='lobby' or human_count()!=3:return {'ok':false,'error':'three_players_required'}
 authority=Authority.new()
 var result:Dictionary=authority.start_match(seed_value)
 if result.ok:_publish_views()
 return result
func submit_command(command:Dictionary)->void:
 if local_view.is_empty():return
 var request:Dictionary={'round':local_view.round,'controller_epoch':local_view.controller_epoch,'sequence':_request_sequence,'command':command}
 _request_sequence+=1
 if is_host:
  command_ack.emit(authority.submit_intent('p0',request));_publish_views()
 else:_send(1,'intent',Codec.pack(request))
func mark_loaded()->void:
 if local_view.is_empty():return
 if is_host:authority.mark_loaded('p0');_publish_views()
 else:_send(1,'loaded',{'round':local_view.round})
func request_next()->void:
 if local_view.is_empty():return
 if is_host:command_ack.emit(authority.request_next('p0'));_publish_views()
 else:_send(1,'next',{'round':local_view.round})
func _publish_views()->void:
 if authority==null or _state.is_empty():return
 var new_phase:String=authority.rules._state.phase
 if phase!=new_phase:
  phase=new_phase;_state.phase=phase;_state.revision+=1
  if phase=='loading':_loading_at=Time.get_ticks_msec()
  _broadcast_state()
 for peer_id in _peers.keys():
  var id:String=_peers[peer_id]
  var view:Dictionary=authority.view_for(id)
  view['names']={}
  for seat in _state.seats:view.names[seat.id]=seat.name
  var battle:String=view.get('battle',{}).get('battle_id','')
  var cursor_key:String=id+':'+battle
  var events:Array=authority.events_since(id,int(_event_cursors.get(cursor_key,0)))
  if events.size()>128:events=events.slice(0,128)
  view['events']=events
  var packed:Dictionary=Codec.pack(view)
  while not events.is_empty() and JSON.stringify(packed).to_utf8_buffer().size()>60000:
   events=events.slice(0,events.size()/2);view.events=events;packed=Codec.pack(view)
  if not events.is_empty():_event_cursors[cursor_key]=events[-1].wire_sequence
  if peer_id==1:local_view=view;view_received.emit(view.duplicate(true))
  else:_send(peer_id,'view',packed)
func _end_match(reason:String)->void:
 for peer_id in _peers.keys():
  if peer_id!=1:_send(peer_id,'error',{'reason':reason})
 _failed(reason)

func _loading_expired(now:int)->bool:return _loading_at>0 and now-_loading_at>120000
