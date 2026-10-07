extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 var folder:String=ProjectSettings.globalize_path('user://lan-process-'+str(Time.get_ticks_usec()));DirAccess.make_dir_recursive_absolute(folder)
 var port:int=31000+int(Time.get_ticks_usec()%1000);var pids:Array=[]
 for role in ['host','a','b']:
  var args:PackedStringArray=['--headless','--path',ProjectSettings.globalize_path('res://'),'--log-file',folder+'/'+role+'.log','--script','res://tests/lan_process_client.gd','--',role,str(port),folder]
  var pid:int=OS.create_process(OS.get_executable_path(),args);pids.append(pid);ck(pid>0,'launch separate '+role)
  if role=='host':await create_timer(0.15).timeout
 var end:int=Time.get_ticks_msec()+12000
 while Time.get_ticks_msec()<end and not FileAccess.file_exists(folder+'/host.json'):await create_timer(0.03).timeout
 var results:Array=[]
 for role in ['host','a','b']:
  var result:Variant=JSON.parse_string(FileAccess.get_file_as_string(folder+'/'+role+'.json')) if FileAccess.file_exists(folder+'/'+role+'.json') else {}
  ck(result is Dictionary and result.get('ok',false),'actual '+role+' handshake succeeded')
  results.append(result)
 if results.all(func(r):return r.get('ok',false)):
  ck(results[0].state==results[1].state and results[1].state==results[2].state,'three independent processes agree on all seats')
  ck(results[0].pid!=results[1].pid and results[1].pid!=results[2].pid,'not an in-process mock')
 for i in range(100):
  if pids.all(func(pid):return not OS.is_process_running(pid)):break
  await create_timer(0.02).timeout
 for pid in pids:
  if OS.is_process_running(pid):OS.kill(pid)
 print('LAN_TRANSPORT_PROCESS checks=',checks,' failures=',failures,' evidence=',folder);quit(1 if failures else 0)
