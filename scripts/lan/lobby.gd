extends Control
const Protocol=preload('res://core/lan/protocol.gd')
signal back_requested
signal start_requested
var room:Node
var nickname:LineEdit
var address:LineEdit
var port:SpinBox
var status:Label
var seats:Label
var create_button:Button
var join_button:Button
var start_button:Button
func _ready()->void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var bg:=ColorRect.new();bg.color=Color('10283e');add_child(bg);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var center:=CenterContainer.new();add_child(center);center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(740,620);box.add_theme_constant_override('separation',14);center.add_child(box)
 _label(box,'局域网好友房',32)
 _label(box,'3 名真人 + 5 个 AI · 同一 Wi-Fi · 三端使用同一版本',18)
 nickname=LineEdit.new();nickname.placeholder_text='你的昵称（最多24字）';nickname.max_length=24;nickname.text='玩家';nickname.custom_minimum_size.y=42;box.add_child(nickname)
 address=LineEdit.new();address.placeholder_text='房主局域网 IPv4 地址';address.custom_minimum_size.y=42;box.add_child(address)
 for ip in IP.get_local_addresses():
  if Protocol.is_lan_address(ip) and not ip.begins_with('127.'):address.text=ip;break
 port=SpinBox.new();port.min_value=1024;port.max_value=65535;port.value=27831;port.prefix='端口 ';box.add_child(port)
 var actions:=HBoxContainer.new();actions.add_theme_constant_override('separation',12);box.add_child(actions)
 create_button=_button(actions,'创建房间',_create)
 join_button=_button(actions,'加入房间',_join)
 start_button=_button(actions,'开始本局',func():start_requested.emit());start_button.disabled=true
 status=_label(box,'创建房间后，把上面的 IP 和端口告诉朋友。',17);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 seats=_label(box,'',18);seats.size_flags_vertical=Control.SIZE_EXPAND_FILL
 _button(box,'离开房间 / 返回主菜单',func():back_requested.emit())
func bind_room(value:Node)->void:
 room=value;room.changed.connect(refresh);room.room_closed.connect(func(reason):status.text=_error(reason);refresh({}))
 refresh(room.snapshot())
func _create()->void:
 if room==null:return
 var result:Dictionary=room.create_room(address.text.strip_edges(),int(port.value),nickname.text.strip_edges())
 if not result.ok:status.text=_error(result.error)
func _join()->void:
 if room==null:return
 var result:Dictionary=room.join_room(address.text.strip_edges(),int(port.value),nickname.text.strip_edges())
 status.text='正在连接房主…' if result.ok else _error(result.error)
func refresh(state:Dictionary)->void:
 var joined:bool=not state.is_empty()
 create_button.disabled=joined;join_button.disabled=joined
 nickname.editable=not joined;address.editable=not joined;port.editable=not joined
 start_button.disabled=not joined or not room.is_host or room.human_count()!=3 or room.phase!='lobby'
 if not joined:seats.text='';return
 status.text=('房主 · ' if room.is_host else '已加入 · ')+str(room.human_count())+'/3 真人到齐'
 var rows:Array[String]=[]
 for seat in state.seats:rows.append('%s  ·  %s'%[seat.name,'真人' if seat.controller=='human' else 'AI' if seat.controller=='ai' else '空位'])
 seats.text='\n'.join(rows)
func _label(parent:Node,text:String,size:int)->Label:
 var node:=Label.new();node.text=text;node.add_theme_font_size_override('font_size',size);node.add_theme_color_override('font_color',Color('eaf7ff'));parent.add_child(node);return node
func _button(parent:Node,text:String,callback:Callable)->Button:
 var node:=Button.new();node.text=text;node.custom_minimum_size=Vector2(220,44);node.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(node);node.pressed.connect(callback);return node
func _error(reason:String)->String:
 return {'version_mismatch':'游戏版本不同，请使用同一个联机版本。','room_full':'房间的三个真人位置已满。','host_disconnected':'房主已离开，房间结束。','host_timeout':'房主连接超时，房间结束。','handshake_timeout':'连接超时，请检查 IP、同网环境及防火墙。','connection_failed':'连接失败，请检查房主 IP、端口与房间状态。','invalid_nickname':'请输入1–24字的昵称。'}.get(reason,'无法连接：'+reason)
