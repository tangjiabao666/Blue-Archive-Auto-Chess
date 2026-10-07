extends SceneTree
## Focused source-process tests. No GUI, export, long battle or thread is used.
const Duel=preload('res://core/offscreen_duel.gd')
var checks:=0
var failures:=0
var Batch
var Wire
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func job(left:String='p1',right:String='p2')->Dictionary:
 return {'left_army':[{'character_id':'serika','star':1,'cell':Vector2(0.123456789,-2)}],
  'right_army':[{'character_id':'yuuka','star':1}],'left_id':left,'right_id':right,'seed':7123456789012345,
  'settings':{'combat_mode':'tactical_v1','tactical_ai_teams':[0,1],'max_ticks':40,'arena_half':9.0,'source_units_per_world_unit':10.0,'random_damage':true,'tactical_damage_scale':0.12345678901234567},
  'arena_config':{'obstacles':[{'rect':Rect2(-2.3,-0.8,0.6,1.6),'blocks_projectiles':true}]}}
func source_result(input:Dictionary)->Dictionary:
 var duel=Duel.new()
 ck(duel.configure(input.left_army,input.right_army,input.left_id,input.right_id,input.seed,input.settings,input.arena_config).is_empty(),'reference source configures')
 duel.run();return duel.result
func write_text(path:String,value:String)->void:
 var file=FileAccess.open(path,FileAccess.WRITE)
 ck(file!=null,'test writes owned fixture')
 if file!=null:file.store_string(value);file.close()
func finish(batch)->Dictionary:
 var until:int=Time.get_ticks_msec()+15000
 var state:Dictionary=batch.poll()
 while state.status=='running' and Time.get_ticks_msec()<until:
  await create_timer(0.01).timeout
  state=batch.poll()
 if state.status=='running':batch.cancel();ck(false,'tiny child terminates within 15 seconds')
 return state
func _initialize()->void:
 call_deferred('_run')
func _run()->void:
 ck(ResourceLoader.exists('res://core/offscreen_process_batch.gd'),'offscreen process batch implementation exists')
 ck(ResourceLoader.exists('res://core/offscreen_process_worker.gd'),'isolated process worker exists')
 if failures:quit(1);return
 Batch=load('res://core/offscreen_process_batch.gd');Wire=load('res://core/offscreen_process_worker.gd')
 var input:Dictionary=job();input.seed=9223372036854775783
 var encoded:Dictionary=Wire.encode_value(input)
 ck(encoded.ok,'typed wire encoder accepts source configuration')
 var parsed=JSON.parse_string(JSON.stringify(encoded.value,'',true,true))
 var decoded:Dictionary=Wire.decode_value(parsed)
 ck(decoded.ok and decoded.value==input,'typed full-precision JSON round trip preserves floats, integers, Vector2 and Rect2')
 ck(decoded.value.settings.tactical_ai_teams[0] is int,'AI team integers retain their source type')
 ck(not Wire.encode_value({'bad':self}).ok,'wire refuses object serialization')
 ck(not Wire.encode_value({'bad':NAN}).ok,'wire refuses nonfinite floats')
 ck(not Wire.encode_value({'bad':'x'.repeat(Wire.MAX_INPUT_BYTES)}).ok,'wire bounds aggregate text before constructing large JSON')
 ck(not Wire.decode_value({'$offscreen':'Vector2','value':[1.0e100,0]}).ok,'wire rejects vector components that overflow native precision')
 ck(Wire.read_json('user://session-save.json',100).error=='invalid_wire_path','wire helper rejects paths outside private process temp root')
 ck(not Wire.decode_value({'$offscreen':'Vector2','value':[0]}).ok,'malformed tagged value fails closed')
 ck(not Wire.decode_value({'$offscreen':'Object','value':'danger'}).ok,'unknown type tag cannot instantiate objects')
 ck(not Wire.decode_value({'$offscreen':'float64','value':'000000000000f07f'}).ok,'nonfinite IEEE float tags are refused')
 var cyclic:Array=[];cyclic.append(cyclic)
 ck(not Wire.encode_value(cyclic).ok,'recursive containers fail a bounded depth guard');cyclic.clear()
 var batch=Batch.new()
 ck(batch.poll().status=='failed','unstarted batch does not invent results')
 for invalid in [[],[{}],[job(),job(),job(),job()]]:
  ck(batch.start(invalid,1).status=='failed','invalid batch rejected without child')
 ck(batch.snapshot().launches==0,'invalid batches never launch a process')
 var bad:Dictionary=job();bad.seed=1.5
 ck(batch.start([bad],1).status=='failed','fractional seed is rejected')
 bad=job();bad.arena_config.obstacles='wrong'
 ck(batch.start([bad],1).status=='failed','invalid obstacles rejected without runtime typed assignment')
 ck(batch.start([job()],-1).status=='failed','negative generation rejected')
 var jobs:Array=[job(),job('p3','p4'),job('p5','p6')];var expected:Array=[]
 for item in jobs:expected.append(source_result(item))
 ck(expected.any(func(value):return value.remaining_hp_ratios.any(func(ratio):return ratio>0.0 and ratio<1.0)),'tiny source test actually damages HP before comparing process metadata')
 var before:Array=jobs.duplicate(true)
 ck(Wire.encode_value(expected).ok,'source result StringName keys encode safely')
 ck(batch.start(jobs,123).status=='running','one child batch starts asynchronously')
 var pid:int=batch.snapshot().pid
 var owned_dir:String=batch._directory
 ck(pid>0 and pid!=OS.get_process_id(),'owned child is a separate engine process')
 ck(batch.snapshot().launches==1 and batch.snapshot().job_count==3,'three duels share one child launch')
 jobs[0].settings.max_ticks=1
 var state:Dictionary=await finish(batch)
 if state.status!='complete' or state.results!=expected:
  printerr('PROCESS_PARITY_STATE ',JSON.stringify(state,'',true,true),' EXPECTED ',JSON.stringify(expected,'',true,true))
  if state.status=='complete':
   for i in range(expected.size()):
    printerr('HPBITS ',var_to_bytes(state.results[i].remaining_hp_ratios).hex_encode(),' ',var_to_bytes(expected[i].remaining_hp_ratios).hex_encode())
 ck(state.status=='complete' and state.results==expected,'three child duels exactly match direct source outcomes and HP metadata')
 ck(before[0].settings.max_ticks==40,'reference fixture remains original')
 ck(not DirAccess.dir_exists_absolute(owned_dir),'successful batch cleans only its owned directory')
 print('PROCESS_PARITY_DIAGNOSTICS ',JSON.stringify(batch.snapshot(),'',true,true))
 var terminal:Dictionary=batch.poll();state.results.clear()
 ck(batch.poll()==terminal and terminal.results.size()==3,'repeated polls return immutable completed results')
 batch.cancel();ck(batch.poll()==terminal,'cancel after completion cannot erase results')
 ck(batch.start([job()],124).status=='running','completed batch can begin a new generation')
 pid=batch.snapshot().pid;owned_dir=batch._directory
 batch.cancel();batch.cancel()
 ck(batch.poll().status=='failed' and batch.poll().error=='cancelled','cancel is idempotent and never publishes a result')
 ck(not FileAccess.file_exists('/proc/'+str(pid)+'/status') if OS.get_name()=='Linux' else batch.snapshot().pid==-1,'cancel relinquishes its terminated owned child')
 ck(not DirAccess.dir_exists_absolute(owned_dir),'cancel removes owned temporary files')
 for mode in ['malformed','stale_nonce','stale_generation','stale_fingerprint','bad_result','extra_field','bad_hp','oversized']:
  ck(batch.start([job()],200).status=='running','fixture child starts for '+mode)
  var envelope:Dictionary=Wire.result_envelope(batch._nonce,200,batch._fingerprint,'complete',[expected[0]],'')
  if mode=='stale_nonce':envelope.nonce='0'.repeat(32)
  if mode=='stale_generation':envelope.generation='199'
  if mode=='stale_fingerprint':envelope.fingerprint='0'.repeat(64)
  if mode=='bad_result':envelope.results=Wire.encode_value([{'ok':true,'outcome':{}}]).value
  if mode=='extra_field':envelope.extra=true
  if mode=='bad_hp':
   var fake:Array=[expected[0].duplicate(true)];fake[0].remaining_hp_ratios[0]=2.0
   envelope.results=Wire.encode_value(fake).value
  write_text(batch._output_path,'{' if mode=='malformed' else 'x'.repeat(Wire.MAX_OUTPUT_BYTES+1) if mode=='oversized' else JSON.stringify(envelope,'',true,true))
  state=batch.poll()
  ck(state.status=='failed' and state.results.is_empty(),mode+' output fails closed')
 ck(batch.start([job()],300).status=='running','timeout fixture starts')
 batch._started_usec=Time.get_ticks_usec()-batch.TIMEOUT_USEC-1
 ck(batch.poll().error=='timeout','deadline failure returns without draining source duels')
 ck(batch.start([job()],302).status=='running','published timeout fixture starts')
 var published:Dictionary=Wire.result_envelope(batch._nonce,302,batch._fingerprint,'complete',[expected[0]],'')
 write_text(batch._output_path,JSON.stringify(published,'',true,true))
 batch._started_usec=Time.get_ticks_usec()-batch.TIMEOUT_USEC-1
 ck(batch.poll().error=='timeout','published output does not bypass a hung worker deadline')
 ck(batch.start([job()],301).status=='running','crash fixture starts')
 pid=batch.snapshot().pid
 # Invalid input makes the real worker exit before publishing. Do not OS.kill
 # here: Godot reaps a killed child and a later is_process_running logs ECHILD.
 write_text(batch._directory+'/request.json','{}')
 state=await finish(batch)
 ck(state.error=='worker_exited','child crash without output fails closed')
 var dying=Batch.new();dying.start([job()],400);pid=dying.snapshot().pid;owned_dir=dying._directory
 dying=null
 ck(not FileAccess.file_exists('/proc/'+str(pid)+'/status') if OS.get_name()=='Linux' else true,'PREDELETE terminates owned child without method dispatch on freed self')
 ck(not DirAccess.dir_exists_absolute(owned_dir),'PREDELETE cleans owned files')
 # A replaced active batch must not leave two children or accept old output.
 batch.start([job()],500);pid=batch.snapshot().pid;owned_dir=batch._directory
 ck(batch.start([job()],501).status=='running','start replaces an active generation')
 ck(batch._directory!=owned_dir and not DirAccess.dir_exists_absolute(owned_dir),'replacement has a fresh nonce and cleans the cancelled generation')
 ck(not FileAccess.file_exists('/proc/'+str(pid)+'/status') if OS.get_name()=='Linux' else true,'replacement terminates its previous child')
 var sibling=Batch.new();sibling.start([job()],502);var sibling_dir:String=sibling._directory
 batch.cancel()
 ck(DirAccess.dir_exists_absolute(sibling_dir),'cancelling one owner preserves sibling temporary files')
 state=await finish(sibling);ck(state.status=='complete','independent sibling completes normally')
 bad=job();bad.settings.unknown_setting=true
 batch.start([job('p3','p4'),bad],600);state=await finish(batch)
 ck(state.status=='failed' and state.results.is_empty() and state.error.begins_with('worker_failed:'),'source configure error returns no partial successful result')
 var variants:Array=[job(),job('p3','p4'),job('p5','p6')]
 variants[0].settings={'max_ticks':40,'source_units_per_world_unit':10.0};variants[1].left_army=[];variants[2].left_army=[];variants[2].right_army=[]
 expected=[]
 for item in variants:expected.append(source_result(item))
 batch.start(variants,700);state=await finish(batch)
 ck(state.status=='complete' and state.results==expected,'legacy and empty-army outcomes also preserve exact result schemas')
 ck(batch.snapshot().cleanup_error.is_empty(),'successful cleanup has no deferred errors')
 var args:PackedStringArray=['--offscreen-process-worker','../escape','1','0'.repeat(64)]
 ck(Wire.run_worker(args)!=0,'worker rejects traversal instead of reading outside private temp root')
 # Exercise the early main-scene dispatch used by standard export templates.
 # This is still a source/Linux headless test, not an exported-Windows claim.
 var nonce:String=Crypto.new().generate_random_bytes(16).hex_encode()
 var directory:String=Wire.ROOT+'/'+nonce;DirAccess.make_dir_recursive_absolute(directory)
 encoded=Wire.encode_value([job()]);var fingerprint:String=Wire.wire_fingerprint(encoded.value)
 var request:Dictionary={'schema':1,'kind':'request','nonce':nonce,'generation':'800','fingerprint':fingerprint,'jobs':encoded.value}
 ck(Wire.write_json_atomic(directory+'/request.json',request,Wire.MAX_INPUT_BYTES).ok,'main-entry fixture writes atomically')
 var worker_args:PackedStringArray=[Wire.FLAG,nonce,'800',fingerprint]
 var malformed:Dictionary=request.duplicate(true);malformed.generation='799'
 Wire.write_json_atomic(directory+'/request.json',malformed,Wire.MAX_INPUT_BYTES)
 ck(Wire.run_worker(worker_args)==4,'worker independently rejects stale request generation')
 malformed=request.duplicate(true);malformed.jobs=[]
 Wire.write_json_atomic(directory+'/request.json',malformed,Wire.MAX_INPUT_BYTES)
 ck(Wire.run_worker(worker_args)==5,'worker independently verifies input fingerprint before simulation')
 write_text(directory+'/request.json','x'.repeat(Wire.MAX_INPUT_BYTES+1))
 ck(Wire.run_worker(worker_args)==3,'worker bounds input bytes before JSON parsing')
 ck(Wire.write_json_atomic(directory+'/request.json',request,Wire.MAX_INPUT_BYTES).ok,'valid main-entry fixture restored')
 args=PackedStringArray(['--headless','--quiet','--path',ProjectSettings.globalize_path('res://'),'--log-file',ProjectSettings.globalize_path(directory+'/worker.log'),'--',Wire.FLAG,nonce,'800',fingerprint])
 pid=OS.create_process(OS.get_executable_path(),args,false)
 ck(pid>0,'headless main-entry child launches without --script')
 var until:int=Time.get_ticks_msec()+15000
 var running:bool=pid>0 and OS.is_process_running(pid)
 while running and Time.get_ticks_msec()<until:
  await create_timer(0.01).timeout
  running=OS.is_process_running(pid)
 if running:OS.kill(pid)
 ck(not running,'main-entry worker exits without entering interactive gameplay')
 var read:Dictionary=Wire.read_json(directory+'/result.json',Wire.MAX_OUTPUT_BYTES)
 ck(read.ok,'main-entry worker publishes an atomic result')
 if read.ok:
  decoded=Wire.decode_value(read.value.results)
  ck(read.value.status=='complete' and decoded.ok and decoded.value==[source_result(job())],'main-entry source duel has identical HP metadata')
 var log_text:String=FileAccess.get_file_as_string(directory+'/worker.log')
 ck(not 'SCRIPT ERROR:' in log_text and not 'ERROR:' in log_text,'main-entry worker has no deferred gameplay script errors')
 ck(Wire.cleanup_files(directory).is_empty(),'main-entry fixture cleans all owned files')
 print('OFFSCREEN_PROCESS_BATCH checks=',checks,' failures=',failures)
 quit(1 if failures else 0)
