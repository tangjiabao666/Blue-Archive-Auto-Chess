extends SceneTree
## The same source duel implementation runs sequentially in one owned engine.
## No objects, Variants, scripts or filesystem paths are accepted from JSON.
const Duel=preload('res://core/offscreen_duel.gd')
const FLAG:='--offscreen-process-worker'
const ROOT:='user://offscreen_process'
const MAX_INPUT_BYTES:=262144
const MAX_OUTPUT_BYTES:=65536
const MAX_NODES:=8192
const MAX_DEPTH:=20
const TAG:='$offscreen'
const JOB_KEYS:=['left_army','right_army','left_id','right_id','seed','settings','arena_config']

func _initialize()->void:
 quit(run_worker(OS.get_cmdline_user_args()))

static func is_worker_request(args:PackedStringArray)->bool:
 return FLAG in args

static func run_worker(args:PackedStringArray)->int:
 if args.size()!=4 or args[0]!=FLAG or not valid_hex(args[1],32) or not valid_integer(args[2]) or int(args[2])<0 or not valid_hex(args[3],64):return 2
 var nonce:String=args[1];var generation:int=int(args[2]);var fingerprint:String=args[3]
 var directory:String=ROOT+'/'+nonce
 var request:Dictionary=read_json(directory+'/request.json',MAX_INPUT_BYTES)
 if not request.ok:return 3
 var envelope:Variant=request.value
 if not envelope is Dictionary or not exact_keys(envelope,['schema','kind','nonce','generation','fingerprint','jobs']):return 4
 if envelope.schema!=1 or envelope.kind!='request' or envelope.nonce!=nonce or envelope.generation!=str(generation) or envelope.fingerprint!=fingerprint:return 4
 if wire_fingerprint(envelope.jobs)!=fingerprint:return 5
 var decoded:Dictionary=decode_value(envelope.jobs)
 if not decoded.ok or not decoded.value is Array:return 6
 var error:String=validate_jobs(decoded.value)
 var results:Array=[]
 if error.is_empty():
  for item in decoded.value:
   var duel=Duel.new()
   error=duel.configure(item.left_army,item.right_army,item.left_id,item.right_id,item.seed,item.settings,item.arena_config)
   if not error.is_empty():break
   duel.run()
   var result:Dictionary=duel.result
   if not result.get('ok',false):error=str(result.get('error','duel_failed'));break
   results.append(result)
 if not error.is_empty():results.clear()
 var output:Dictionary=result_envelope(nonce,generation,fingerprint,'complete' if error.is_empty() else 'failed',results,error)
 var written:Dictionary=write_json_atomic(directory+'/result.json',output,MAX_OUTPUT_BYTES)
 return 0 if written.ok and error.is_empty() else 7

static func result_envelope(nonce:String,generation:int,fingerprint:String,status:String,results:Array,error:String)->Dictionary:
 var encoded:Dictionary=encode_value(results)
 return {'schema':1,'kind':'result','nonce':nonce,'generation':str(generation),'fingerprint':fingerprint,
  'status':status if encoded.ok else 'failed','results':encoded.value if encoded.ok else [],'error':error if encoded.ok else encoded.error}

static func validate_jobs(jobs:Array)->String:
 if jobs.is_empty() or jobs.size()>3:return 'invalid_job_count'
 var seen:Dictionary={}
 for item in jobs:
  if not item is Dictionary or not exact_keys(item,JOB_KEYS):return 'invalid_job_schema'
  if not item.seed is int:return 'invalid_seed'
  if not item.settings is Dictionary or not item.arena_config is Dictionary:return 'invalid_settings'
  for key in ['left_id','right_id']:
   if not item[key] is String or item[key] not in Duel.RIVALS or seen.has(item[key]):return 'invalid_participants'
   seen[item[key]]=true
  for key in ['left_army','right_army']:
   if not item[key] is Array or item[key].size()>6:return 'invalid_army'
   for unit in item[key]:
    if not unit is Dictionary or not unit.get('character_id') is String or unit.character_id.is_empty() or unit.character_id.length()>64:return 'invalid_source_unit'
    if typeof(unit.get('star')) not in [TYPE_INT,TYPE_FLOAT] or unit.star not in [1,2]:return 'invalid_source_star'
  if item.arena_config.has('obstacles'):
   if not item.arena_config.obstacles is Array or item.arena_config.obstacles.size()>64:return 'invalid_obstacles'
   for obstacle in item.arena_config.obstacles:
    if not obstacle is Dictionary or not obstacle.get('rect') is Rect2 or not obstacle.get('blocks_projectiles') is bool:return 'invalid_obstacle'
 return ''

static func validate_results(results:Variant,jobs:Array)->String:
 if not results is Array or results.size()!=jobs.size():return 'invalid_result_count'
 for index in range(jobs.size()):
  var result:Variant=results[index];var item:Dictionary=jobs[index]
  var tactical:bool=item.settings.get('combat_mode','legacy')=='tactical_v1'
  var keys:Array=['ok','outcome','remaining_hp_ratios'] if tactical else ['ok','outcome']
  if not result is Dictionary or not exact_keys(result,keys) or not result.ok is bool or not result.ok:return 'invalid_result'
  var outcome:Variant=result.outcome
  var hp_timeout:bool=tactical and item.settings.get('timeout_total_hp',false)
  var outcome_keys:Array=['left_id','right_id','winner','left_remaining','right_remaining','duration_ticks','finish_reason']
  if hp_timeout:outcome_keys.append_array(['remaining_hp_totals','maximum_hp_totals'])
  if not outcome is Dictionary or not exact_keys(outcome,outcome_keys):return 'invalid_outcome'
  if outcome.left_id!=item.left_id or outcome.right_id!=item.right_id:return 'mismatched_participants'
  if not outcome.left_remaining is int or not outcome.right_remaining is int or outcome.left_remaining<0 or outcome.left_remaining>item.left_army.size() or outcome.right_remaining<0 or outcome.right_remaining>item.right_army.size():return 'invalid_survivors'
  var expected:String='left' if outcome.left_remaining>0 and outcome.right_remaining==0 else 'right' if outcome.right_remaining>0 and outcome.left_remaining==0 else 'draw'
  if hp_timeout:
   if not preload('res://core/battle_outcome.gd').valid(outcome,item.left_army.size(),item.right_army.size(),int(item.settings.get('max_ticks',72000))):return 'invalid_hp_winner'
  elif outcome.winner!=expected:return 'invalid_winner'
  if not outcome.duration_ticks is int or outcome.duration_ticks<0 or outcome.duration_ticks>int(item.settings.get('max_ticks',72000)):return 'invalid_duration'
  if outcome.finish_reason not in ['empty','timeout','elimination']:return 'invalid_finish_reason'
  if tactical:
   if not result.remaining_hp_ratios is Array or result.remaining_hp_ratios.size()!=2:return 'invalid_hp_metadata'
   for ratio in result.remaining_hp_ratios:
    if typeof(ratio) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(ratio)) or ratio<0 or ratio>1:return 'invalid_hp_ratio'
   if hp_timeout:
    var actual:Array=preload('res://core/battle_outcome.gd').ratios(outcome)
    for side in range(2):
     if absf(float(result.remaining_hp_ratios[side])-float(actual[side]))>0.000000000001:return 'inconsistent_hp_ratio'
 return ''

## Integers are tagged decimal strings to preserve both 64-bit precision and
## int-vs-float semantics (the simulator requires int seeds, ticks and AI teams).
static func encode_value(value:Variant)->Dictionary:
 var state:Dictionary={'nodes':0,'bytes':0,'error':''}
 var encoded:Variant=_encode(value,state,0)
 return {'ok':state.error.is_empty(),'value':encoded,'error':state.error}

static func _encode(value:Variant,state:Dictionary,depth:int)->Variant:
 if not _visit(state,depth):return null
 match typeof(value):
  TYPE_NIL,TYPE_BOOL:return value
  TYPE_INT:return {TAG:'int','value':str(value)}
  TYPE_FLOAT:
   if is_finite(value):return _float_wire(value)
  TYPE_STRING,TYPE_STRING_NAME:
   state.bytes+=str(value).length()*6
   if state.bytes<=MAX_INPUT_BYTES:return str(value)
  TYPE_VECTOR2:
   if is_finite(value.x) and is_finite(value.y):return {TAG:'Vector2','value':[_float_wire(value.x),_float_wire(value.y)]}
  TYPE_RECT2:
   if is_finite(value.position.x) and is_finite(value.position.y) and is_finite(value.size.x) and is_finite(value.size.y):return {TAG:'Rect2','value':[_float_wire(value.position.x),_float_wire(value.position.y),_float_wire(value.size.x),_float_wire(value.size.y)]}
  TYPE_ARRAY:
   if value.size()>MAX_NODES:state.error='wire_too_large';return null
   var array:Array=[]
   for child in value:
    array.append(_encode(child,state,depth+1))
    if not state.error.is_empty():return null
   return array
  TYPE_DICTIONARY:
   if value.size()>MAX_NODES or value.has(TAG):state.error='invalid_wire_dictionary';return null
   var dictionary:Dictionary={}
   for key in value:
    if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or str(key).length()>256:state.error='invalid_wire_key';return null
    state.bytes+=str(key).length()*6
    dictionary[str(key)]=_encode(value[key],state,depth+1)
    if not state.error.is_empty():return null
   return dictionary
 state.error='unsupported_wire_value';return null

static func decode_value(value:Variant)->Dictionary:
 var state:Dictionary={'nodes':0,'bytes':0,'error':''}
 var decoded:Variant=_decode(value,state,0)
 return {'ok':state.error.is_empty(),'value':decoded,'error':state.error}

static func _decode(value:Variant,state:Dictionary,depth:int)->Variant:
 if not _visit(state,depth):return null
 if value is Dictionary and value.has(TAG):
  if not exact_keys(value,[TAG,'value']) or not value[TAG] is String:state.error='invalid_wire_tag';return null
  if value[TAG]=='int':
   if value.value is String and valid_integer(value.value):return int(value.value)
  elif value[TAG]=='float64':
   if value.value is String and valid_hex(value.value,16):
    var number:float=value.value.hex_decode().decode_double(0)
    if is_finite(number):return number
  elif value[TAG] in ['Vector2','Rect2']:
   if value.value is Array and value.value.size()==(2 if value[TAG]=='Vector2' else 4):
    var coordinates:Array=[];var valid:=true
    for raw in value.value:
     var number:Variant=_decode(raw,state,depth+1)
     if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)):valid=false
     coordinates.append(number)
    if valid and state.error.is_empty():
     var position:Vector2=Vector2(coordinates[0],coordinates[1])
     if value[TAG]=='Vector2' and position.is_finite():return position
     if value[TAG]=='Rect2':
      var size:Vector2=Vector2(coordinates[2],coordinates[3])
      if position.is_finite() and size.is_finite():return Rect2(position,size)
  state.error='invalid_wire_tag';return null
 if value is Array:
  if value.size()>MAX_NODES:state.error='wire_too_large';return null
  var array:Array=[]
  for child in value:
   array.append(_decode(child,state,depth+1))
   if not state.error.is_empty():return null
  return array
 if value is Dictionary:
  if value.size()>MAX_NODES:state.error='wire_too_large';return null
  var dictionary:Dictionary={}
  for key in value:
   if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME] or str(key).length()>256:state.error='invalid_wire_key';return null
   dictionary[key]=_decode(value[key],state,depth+1)
   if not state.error.is_empty():return null
  return dictionary
 if typeof(value) in [TYPE_NIL,TYPE_BOOL]:return value
 if value is String and value.length()<=MAX_INPUT_BYTES:return value
 if typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)):return float(value)
 state.error='unsupported_wire_value';return null

static func _visit(state:Dictionary,depth:int)->bool:
 state.nodes+=1;state.bytes+=64
 if depth>MAX_DEPTH or state.nodes>MAX_NODES or state.bytes>MAX_INPUT_BYTES:state.error='wire_too_large'
 return state.error.is_empty()

## Godot's decimal JSON parser can move a full-precision decimal by one ULP.
## Fixed 8-byte IEEE values preserve exact HP totals without Variant decoding.
static func _float_wire(value:float)->Dictionary:
 var bytes:PackedByteArray=[];bytes.resize(8);bytes.encode_double(0,value)
 return {TAG:'float64','value':bytes.hex_encode()}

static func valid_integer(value:String)->bool:
 return value.length()<=20 and value.is_valid_int() and str(int(value))==value

static func valid_hex(value:String,length:int)->bool:
 if value.length()!=length:return false
 for character in value:
  if character not in '0123456789abcdef':return false
 return true

static func exact_keys(value:Dictionary,keys:Array)->bool:
 if value.size()!=keys.size():return false
 for key in keys:
  if not value.has(key):return false
 return true

static func wire_fingerprint(value:Variant)->String:
 return JSON.stringify(value,'',true,true).sha256_text()

static func read_json(path:String,max_bytes:int)->Dictionary:
 if not valid_file_path(path):return {'ok':false,'error':'invalid_wire_path'}
 var file=FileAccess.open(path,FileAccess.READ)
 if file==null:return {'ok':false,'error':'file_open_failed'}
 var size:int=file.get_length()
 if size<=0 or size>max_bytes:file.close();return {'ok':false,'error':'invalid_file_size'}
 var bytes:PackedByteArray=file.get_buffer(size);file.close()
 if bytes.size()!=size:return {'ok':false,'error':'file_read_failed'}
 var parser=JSON.new()
 if parser.parse(bytes.get_string_from_utf8())!=OK:return {'ok':false,'error':'malformed_json'}
 return {'ok':true,'value':parser.data,'error':''}

static func write_json_atomic(path:String,value:Dictionary,max_bytes:int)->Dictionary:
 if not valid_file_path(path):return {'ok':false,'error':'invalid_wire_path'}
 var contents:String=JSON.stringify(value,'',true,true)
 if contents.to_utf8_buffer().size()>max_bytes:return {'ok':false,'error':'file_too_large'}
 var file=FileAccess.open(path+'.tmp',FileAccess.WRITE)
 if file==null:return {'ok':false,'error':'file_write_failed'}
 file.store_string(contents);file.flush();var error:Error=file.get_error();file.close()
 if error!=OK:return {'ok':false,'error':'file_write_failed'}
 error=DirAccess.rename_absolute(path+'.tmp',path)
 return {'ok':error==OK,'error':'' if error==OK else 'atomic_rename_failed'}

## Only a validated owner-created nonce directory and fixed known filenames
## may be removed. Never scan, recursively delete or accept a supplied path.
static func valid_file_path(path:String)->bool:
 if not path.begins_with(ROOT+'/'):return false
 var parts:PackedStringArray=path.trim_prefix(ROOT+'/').split('/')
 return parts.size()==2 and valid_hex(parts[0],32) and parts[1] in ['request.json','result.json']

static func cleanup_files(directory:String)->String:
 if directory.is_empty():return ''
 if not directory.begins_with(ROOT+'/') or not valid_hex(directory.trim_prefix(ROOT+'/'),32):return 'invalid_cleanup_owner'
 var error:=''
 for name in ['request.json','request.json.tmp','result.json','result.json.tmp','worker.log']:
  var path:String=directory+'/'+name
  if FileAccess.file_exists(path) and DirAccess.remove_absolute(path)!=OK:error='temp_cleanup_failed'
 if DirAccess.dir_exists_absolute(directory) and DirAccess.remove_absolute(directory)!=OK:error='temp_cleanup_failed'
 return error
