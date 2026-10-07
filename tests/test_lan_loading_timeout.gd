extends SceneTree
func _initialize():call_deferred('run')
func run():
 var room=load('res://scripts/lan/room_controller.gd').new();root.add_child(room)
 room.is_host=false;room._loading_at=1000
 assert(not room._loading_expired(120999) and room._loading_expired(121001))
 room.phase='loading';room._last_received[1]=Time.get_ticks_msec()-20000;room._process(0.0)
 assert(room.phase=='loading' and room.last_error.is_empty())
 room.phase='preparation';room._process(0.0)
 assert(room.phase=='idle' and room.last_error=='host_timeout')
 room.queue_free();await process_frame;print('LAN_LOADING_TIMEOUT PASS loading uses independent grace');quit()
