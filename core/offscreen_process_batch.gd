extends RefCounted
## One main-thread-owned subprocess for an entire round. Normal polling never
## drains a duel or waits for exit. Failure/cancel kills only this owned child.
## No GDScript threads are used; callers can fall back to cooperative jobs.
## Preload also makes the worker and its source-duel dependencies export-visible.
const Worker=preload('res://core/offscreen_process_worker.gd')
const TIMEOUT_USEC:=120000000
var _status:='failed'
var _error:='not_started'
var _results:Array=[]
var _jobs:Array=[]
var _pid:=-1
var _generation:=0
var _nonce:=''
var _fingerprint:=''
var _directory:=''
var _output_path:=''
var _started_usec:=0
var _finished_usec:=0
var _polls:=0
var _last_poll_usec:=0
var _max_poll_usec:=0
var _launches:=0
var _cleanup_error:=''

func start(jobs:Array,generation:int)->Dictionary:
 if _status=='running':cancel()
 if _cleanup_error=='process_termination_failed':return _fail('process_termination_failed')
 if not _directory.is_empty():
  _cleanup()
  if not _directory.is_empty():return _fail('cleanup_pending')
 _results=[];_jobs=[];_status='failed';_error='';_generation=generation
 _polls=0;_last_poll_usec=0;_max_poll_usec=0;_started_usec=Time.get_ticks_usec();_finished_usec=0
 if generation<0:return _fail('invalid_generation')
 var encoded:Dictionary=Worker.encode_value(jobs)
 if not encoded.ok:return _fail(encoded.error)
 var error:String=Worker.validate_jobs(jobs)
 if not error.is_empty():return _fail(error)
 if OS.get_name() not in ['Linux','Windows','macOS','FreeBSD','NetBSD','OpenBSD','BSD']:return _fail('unsupported_process_platform')
 _jobs=jobs.duplicate(true)
 _nonce=Crypto.new().generate_random_bytes(16).hex_encode()
 if not Worker.valid_hex(_nonce,32):return _fail('nonce_failed')
 _fingerprint=Worker.wire_fingerprint(encoded.value)
 _directory=Worker.ROOT+'/'+_nonce;_output_path=_directory+'/result.json'
 # A nonce collision must never authorize removing another batch's files.
 if DirAccess.dir_exists_absolute(_directory):_directory='';return _fail('nonce_collision')
 if DirAccess.make_dir_recursive_absolute(_directory)!=OK:return _fail('temp_directory_failed')
 var request:Dictionary={'schema':1,'kind':'request','nonce':_nonce,'generation':str(generation),'fingerprint':_fingerprint,'jobs':encoded.value}
 var written:Dictionary=Worker.write_json_atomic(_directory+'/request.json',request,Worker.MAX_INPUT_BYTES)
 if not written.ok:return _fail(written.error)
 var args:PackedStringArray=['--headless','--quiet','--log-file',ProjectSettings.globalize_path(_directory+'/worker.log')]
 if OS.has_feature('editor'):
  args.append_array(['--path',ProjectSettings.globalize_path('res://'),'--script','res://core/offscreen_process_worker.gd'])
 # Standard export templates disable --script/--path. Their main scene must
 # dispatch Worker.is_worker_request/run_worker before creating the game UI.
 args.append_array(['--',Worker.FLAG,_nonce,str(generation),_fingerprint])
 _pid=OS.create_process(OS.get_executable_path(),args,false)
 if _pid<=0:return _fail('process_launch_failed')
 _launches+=1;_status='running';_error=''
 return _state()

func poll()->Dictionary:
 if _status!='running':
  if not _directory.is_empty():_cleanup()
  return _state()
 var before:int=Time.get_ticks_usec();_polls+=1
 if Time.get_ticks_usec()-_started_usec>=TIMEOUT_USEC:_fail('timeout')
 elif FileAccess.file_exists(_output_path):
  var read:Dictionary=Worker.read_json(_output_path,Worker.MAX_OUTPUT_BYTES)
  if not read.ok:_fail(read.error)
  else:_accept_output(read.value)
 elif _pid<=0 or not OS.is_process_running(_pid):
  # The writer renames before exiting; check once again after observing exit
  # in case it published between the first existence check and the OS query.
  _pid=-1
  if FileAccess.file_exists(_output_path):
   var read:Dictionary=Worker.read_json(_output_path,Worker.MAX_OUTPUT_BYTES)
   if not read.ok:_fail(read.error)
   else:_accept_output(read.value)
  else:_fail('worker_exited')
 _last_poll_usec=Time.get_ticks_usec()-before;_max_poll_usec=maxi(_max_poll_usec,_last_poll_usec)
 return _state()

func cancel()->void:
 if _status=='running':_fail('cancelled')

func snapshot()->Dictionary:
 return {'status':_status,'error':_error,'generation':_generation,'job_count':_jobs.size(),'pid':_pid,'launches':_launches,
  'elapsed_usec':(_finished_usec if _finished_usec>0 else Time.get_ticks_usec())-_started_usec if _started_usec>0 else 0,
  'polls':_polls,'last_poll_usec':_last_poll_usec,'max_poll_usec':_max_poll_usec,'cleanup_error':_cleanup_error}

func _accept_output(envelope:Variant)->void:
 if not envelope is Dictionary or not Worker.exact_keys(envelope,['schema','kind','nonce','generation','fingerprint','status','results','error']):_fail('invalid_result_envelope');return
 if envelope.schema!=1 or envelope.kind!='result' or envelope.nonce!=_nonce or envelope.generation!=str(_generation) or envelope.fingerprint!=_fingerprint:_fail('stale_result_envelope');return
 if envelope.status not in ['complete','failed'] or not envelope.error is String or envelope.error.length()>512:_fail('invalid_result_status');return
 var decoded:Dictionary=Worker.decode_value(envelope.results)
 if not decoded.ok or not decoded.value is Array:_fail('invalid_result_encoding');return
 if envelope.status=='failed':
  if not decoded.value.is_empty() or envelope.error.is_empty():_fail('invalid_failure_envelope');return
  _fail('worker_failed: '+envelope.error);return
 if not envelope.error.is_empty():_fail('invalid_success_envelope');return
 var error:String=Worker.validate_results(decoded.value,_jobs)
 if not error.is_empty():_fail(error);return
 # Publication precedes process shutdown. Let a successful child exit on its
 # own; OS.kill reaps synchronously on Unix and is reserved for cancellation.
 if _pid>0 and OS.is_process_running(_pid):return
 _pid=-1
 _results=decoded.value.duplicate(true);_status='complete';_error='';_finished_usec=Time.get_ticks_usec();_cleanup()

func _state()->Dictionary:
 return {'status':_status,'results':_results.duplicate(true),'error':_error}

func _fail(error:String)->Dictionary:
 _status='failed';_error=error;_results=[];_finished_usec=Time.get_ticks_usec();_cleanup()
 return _state()

func _cleanup()->void:
 # The only stored PID originates in this object's successful create_process.
 # Never retain a PID after observing exit or attempt to terminate it again.
 if _pid>0:
  if OS.is_process_running(_pid):
   var killed:Error=OS.kill(_pid)
   if killed!=OK:_cleanup_error='process_termination_failed'
  _pid=-1
 var files_error:String=Worker.cleanup_files(_directory)
 if not files_error.is_empty():
  if _cleanup_error!='process_termination_failed':_cleanup_error=files_error
 else:
  _directory='';_output_path=''
  if _cleanup_error!='process_termination_failed':_cleanup_error=''
 # Keep an unsuccessful directory cleanup for the next poll/start. Windows
 # TerminateProcess may return before the log handle has been released.

func _notification(what:int)->void:
 if what!=NOTIFICATION_PREDELETE:return
 # RefCounted is already at zero here: no instance-method calls on self.
 if _pid>0 and OS.is_process_running(_pid):OS.kill(_pid)
 _pid=-1
 Worker.cleanup_files(_directory)
