extends SceneTree
var room
var role:String
var directory:String
var end:int
func _initialize():call_deferred('run')
func run():
 var args:PackedStringArray=OS.get_cmdline_user_args();role=args[0];directory=args[2];end=Time.get_ticks_msec()+10000
 room=load('res://scripts/lan/room_controller.gd').new();room.name='Room';root.add_child(room)
 var result:Dictionary=room.create_room('127.0.0.1',int(args[1]),'Host') if role=='host' else room.join_room('127.0.0.1',int(args[1]),role)
 if not result.ok:finish(false);return
 while Time.get_ticks_msec()<end:
  if not room.last_error.is_empty():finish(false);return
  if room.human_count()==3:
   if role!='host' or (FileAccess.file_exists(directory+'/a.json') and FileAccess.file_exists(directory+'/b.json')):finish(true);return
  await create_timer(0.02).timeout
 finish(false)
func finish(ok:bool):
 var file=FileAccess.open(directory+'/'+role+'.json',FileAccess.WRITE)
 file.store_string(JSON.stringify({'ok':ok,'pid':OS.get_process_id(),'role':role,'local_id':room.local_participant_id,'state':room.snapshot(),'error':room.last_error}));file.close()
 if role=='host':room.leave_room()
 else:
  # Keep both clients connected until the host observes their receipts.
  for i in range(100):
   if room.phase=='idle':break
   await create_timer(0.02).timeout
 room.queue_free();await process_frame;quit(0 if ok else 1)
