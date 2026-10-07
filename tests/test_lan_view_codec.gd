extends SceneTree
const Codec=preload('res://core/lan/view_codec.gd')
const View=preload('res://core/lan/session_view.gd')
func _initialize():
 var value={'point':Vector2(1.25,-2.5),'rect':Rect2(1,2,3,4),'map':{0:9,1:[Vector2.ZERO]},'int':4}
 assert(Codec.unpack(JSON.parse_string(JSON.stringify(Codec.pack(value))))==value)
 var a=load('res://core/lan/authority.gd').new();a.start_match(1)
 var state:Dictionary=Codec.unpack(JSON.parse_string(JSON.stringify(Codec.pack(a.view_for('p1')))))
 var view=View.new();assert(view.accept(state,'p1').ok);assert(not view.accept(state,'p2').ok)
 state.player.gold=999;assert(view.state.player.gold!=999)
 a.close();print('LAN_VIEW_CODEC PASS');quit()
