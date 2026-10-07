extends Node
const Protocol=preload('res://core/lan/protocol.gd')
signal message_received(peer_id:int,message:Dictionary)
signal peer_joined(peer_id:int)
signal peer_left(peer_id:int)
signal connected
signal failed(reason:String)
var api:SceneMultiplayer
var peer:ENetMultiplayerPeer
var _budgets:Dictionary={}
var _generation:=0
func _ready()->void:
 api=SceneMultiplayer.new();api.server_relay=false;api.allow_object_decoding=false
 get_tree().set_multiplayer(api,get_path())
 api.peer_connected.connect(func(id):call_deferred('_notify','joined',id,_generation))
 api.peer_disconnected.connect(func(id):call_deferred('_notify','left',id,_generation))
 api.connected_to_server.connect(func():call_deferred('_notify','connected',0,_generation))
 api.connection_failed.connect(func():call_deferred('_notify','failed',0,_generation))
 api.server_disconnected.connect(func():call_deferred('_notify','left',1,_generation))
func host(bind_ip:String,port:int)->Error:
 close()
 if not Protocol.is_lan_address(bind_ip) or port<1024 or port>65535:return ERR_INVALID_PARAMETER
 peer=ENetMultiplayerPeer.new();peer.set_bind_ip(bind_ip)
 var error:Error=peer.create_server(port,8,2)
 if error!=OK:peer=null;return error
 api.multiplayer_peer=peer;return OK
func join(ip:String,port:int)->Error:
 close()
 if not Protocol.is_lan_address(ip) or port<1024 or port>65535:return ERR_INVALID_PARAMETER
 peer=ENetMultiplayerPeer.new()
 var error:Error=peer.create_client(ip,port,2)
 if error!=OK:peer=null;return error
 api.multiplayer_peer=peer;return OK
func send_to(peer_id:int,message:Dictionary)->void:
 if peer==null or peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return
 var bytes:PackedByteArray=Protocol.encode(message)
 if bytes.is_empty():failed.emit('invalid_outgoing_message');return
 if message.type=='view':_view_packet.rpc_id(peer_id,bytes)
 else:_packet.rpc_id(peer_id,bytes)
func disconnect_peer(peer_id:int)->void:
 call_deferred('_disconnect_peer',peer_id,_generation)
func _disconnect_peer(peer_id:int,generation:int)->void:
 if generation!=_generation:return
 if peer!=null and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:peer.disconnect_peer(peer_id)
func close()->void:
 _generation+=1
 if peer!=null:peer.close();peer=null
 if api!=null:api.multiplayer_peer=OfflineMultiplayerPeer.new()
 _budgets.clear()
@rpc('any_peer','call_remote','reliable',0)
func _packet(bytes:PackedByteArray)->void:_receive(bytes)
@rpc('authority','call_remote','reliable',1)
func _view_packet(bytes:PackedByteArray)->void:_receive(bytes)
func _receive(bytes:PackedByteArray)->void:
 var sender:int=api.get_remote_sender_id();var now:int=Time.get_ticks_msec()
 var budget:Dictionary=_budgets.get(sender,{'at':now,'count':0})
 if now-int(budget.at)>=1000:budget={'at':now,'count':0}
 budget.count+=1;_budgets[sender]=budget
 if api.is_server() and budget.count>120:disconnect_peer(sender);return
 var decoded:Dictionary=Protocol.decode(bytes)
 if not decoded.ok:disconnect_peer(sender);return
 call_deferred('_deliver',sender,decoded.message,_generation)
func _exit_tree()->void:
 close()
 if get_tree()!=null:get_tree().set_multiplayer(null,get_path())

func _deliver(sender:int,message:Dictionary,generation:int)->void:
 if generation==_generation and peer!=null:message_received.emit(sender,message)
func _notify(kind:String,id:int,generation:int)->void:
 if generation!=_generation or peer==null:return
 match kind:
  'joined':peer_joined.emit(id)
  'left':_budgets.erase(id);peer_left.emit(id)
  'connected':connected.emit()
  'failed':failed.emit('connection_failed')
