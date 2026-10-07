extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 var stored:Dictionary={}
 for path in ['user://session-save.json','user://session-save.json.bak']:
  stored[path]=FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
  var file=FileAccess.open(path,FileAccess.WRITE);file.store_string('LAN-storage-isolation-sentinel:'+path);file.close()
 for mode in ['normal','drop']:
  var folder:String=ProjectSettings.globalize_path('user://lan-match-'+mode+'-'+str(Time.get_ticks_usec()));DirAccess.make_dir_recursive_absolute(folder)
  var port:int=35000+int(Time.get_ticks_usec()%1000);var pids:Array=[]
  for role in ['host','a','b']:
   var args:PackedStringArray=['--headless','--path',ProjectSettings.globalize_path('res://'),'--log-file',folder+'/'+role+'.log','--script','res://tests/lan_match_process_client.gd','--',role,str(port),folder,mode]
   var pid:int=OS.create_process(OS.get_executable_path(),args);pids.append(pid);ck(pid>0,'launch '+mode+' '+role)
   if role=='host':await create_timer(0.2).timeout
  var end:int=Time.get_ticks_msec()+160000
  while Time.get_ticks_msec()<end and not FileAccess.file_exists(folder+'/host.json'):await create_timer(0.1).timeout
  var results:Array=[]
  for role in ['host','a','b']:
   var result:Variant=JSON.parse_string(FileAccess.get_file_as_string(folder+'/'+role+'.json')) if FileAccess.file_exists(folder+'/'+role+'.json') else {}
   ck(result is Dictionary and result.get('ok',false),mode+' '+role+' completed');results.append(result)
  if results.all(func(r):return r.get('ok',false)):
   ck(results[0].rounds.map(func(v):return int(v))==[1,2,3,4,5,6] and results[0].reason=='finished',mode+' host six rounds')
   ck(results[0].max_bytes<65500 and results[1].max_bytes<65500 and results[2].max_bytes<65500,'bounded wire packets')
   if mode=='normal':
    ck(results[0].standings==results[1].standings and results[1].standings==results[2].standings,'all three final standings identical')
    ck(results[1].team1 or results[2].team1,'nonhost receives team1')
   else:ck(results[0].controllers.p1=='ai' and results[0].controllers.p2=='ai','both dropped clients continue as AI to final')
  for i in range(100):
   if pids.all(func(pid):return not OS.is_process_running(pid)):break
   await create_timer(0.03).timeout
  for pid in pids:
   if OS.is_process_running(pid):OS.kill(pid)
  print('LAN_MATCH_EVIDENCE ',folder)
 for path in stored:
  ck(FileAccess.get_file_as_string(path)=='LAN-storage-isolation-sentinel:'+path,'offline checkpoint untouched')
  if stored[path]==null:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
  else:
   var file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(stored[path]);file.close()
 print('LAN_THREE_PROCESS_MATCH checks=',checks,' failures=',failures);quit(1 if failures else 0)
