extends "res://scripts/native_combat_audio.gd"
## Official waveforms; deliberately adapted render-state playback, NOT recovered
## AudioAnimator runtime parity. Existing EX/basic loading remains untouched.
const ORDINARY_MANIFEST="res://data/audio/native-ordinary-sfx.json"
const STATES=["Base Layer.Normal.AttackIng","Base Layer.Normal.Reload"]
var _attack_contacts:Dictionary={}
var _assets:Dictionary={}
var _states:Dictionary={}
var _choices:Array=[]
var _battle_seed:int=0
var _cancelled_state:int=0
var _invalid_states:int=0
func _init()->void:
 max_voices=12
func begin_battle(units:Array,new_generation:int,battle_seed:int)->void:
 begin_roster(units,new_generation);_battle_seed=battle_seed
func reset(new_generation:int)->void:
 super.reset(new_generation)
 _attack_contacts.clear();_states.clear();_choices.clear();_battle_seed=0;_cancelled_state=0;_invalid_states=0
func consume(event:Dictionary)->void:
 if _draining:return
 if str(event.get("type",""))=="death":super.consume(event);return
 if event.get("type")!="attack":return
 if not _whole(event.get("generation")) or int(event.generation)!=generation:_stats.stale_events+=1;return
 if not _whole(event.get("actor_id")) or not _characters.has(int(event.actor_id)):return
 if not _text(event.get("event_id")) or str(event.event_id).is_empty() or str(event.event_id).length()>1024:return
 if not _whole(event.get("tick")) or not _whole(event.get("impact_tick")):return
 if event.tick<0 or event.impact_tick<event.tick or event.impact_tick>10000000:return
 var key:String=str(int(event.actor_id))+":"+str(event.event_id)
 if _attack_contacts.has(key):return
 if _attack_contacts.size()>=maxi(0,max_seen_actions):_stats.seen_budget_drops+=1;return
 _attack_contacts[key]=float(event.impact_tick)*TICK_SECONDS
func consume_state(record:Dictionary)->void:
 if _draining:return
 if not _whole(record.get("generation")) or int(record.generation)!=generation:
  _stats.stale_events+=1;return
 if not _whole(record.get("actor_id")) or not _text(record.get("token")):
  _invalid_states+=1;return
 var actor:int=int(record.actor_id);var token:String=str(record.token)
 if not _characters.has(actor) or token.is_empty() or token.length()>1024:return
 var key:String=str(actor)+":"+token
 var kind:String=str(record.get("type",""))
 if kind=="exit":
  if not _number(record.get("at")) or float(record.at)<0:_invalid_states+=1;return
  if not _states.has(key) and _states.size()>=maxi(0,max_seen_actions):_stats.seen_budget_drops+=1;return
  var value:Dictionary=_states.get(key,{"entered":false})
  value.exit_at=minf(float(value.get("exit_at",INF)),float(record.at));_states[key]=value
  _prune_state_cues();return
 if kind!="enter":_invalid_states+=1;return
 for field in ["character_id","action_id","state_name","native_clip"]:
  if not _text(record.get(field)) or str(record[field]).is_empty() or str(record[field]).length()>1024:_invalid_states+=1;return
 if str(record.character_id)!=str(_characters[actor]):_invalid_states+=1;return
 for field in ["start_time","source_offset","speed","planned_end_time"]:
  if not _number(record.get(field)):_invalid_states+=1;return
 var start:float=float(record.start_time);var speed:float=float(record.speed);var ending:float=float(record.planned_end_time)
 if start<0 or speed<=0 or speed>1000 or ending<=start or float(record.source_offset)!=0.0:_invalid_states+=1;return
 var binding_key:String=str(record.character_id)+":"+str(record.state_name)
 var row:Dictionary=_bindings.get(binding_key,{})
 if row.is_empty() or str(row.native_clip)!=str(record.native_clip):_invalid_states+=1;return
 if bool(_states.get(key,{}).get("entered",false)):_stats.duplicates+=1;return
 if not _states.has(key) and _states.size()>=maxi(0,max_seen_actions):_stats.seen_budget_drops+=1;return
 var end_at:float=minf(ending,float(_states.get(key,{}).get("exit_at",INF)))
 _states[key]={"entered":true,"exit_at":end_at};_seen_actions[key]=true
 if start>=float(_dead_at.get(actor,INF)):_stats.cancelled_death+=1;return
 # Keep source timing as evidence; the PC combat adapter aligns one complete
 # firing waveform to its authoritative attack contact, not every damage/echo.
 var source_onset:float=start+float(row.raw_delay)/speed
 var onset:float=source_onset
 var contact_key:String=str(actor)+":"+str(record.action_id)
 if str(record.state_name)=="Base Layer.Normal.AttackIng" and _attack_contacts.has(contact_key):onset=float(_attack_contacts[contact_key])
 var choice_index:int=_choice_index(actor,str(record.action_id),binding_key,row.clips.size())
 var clip_name:String=str(row.clips[choice_index]);var path:String=str(_assets[clip_name].path)
 _remember(_choices,{"actor_id":actor,"action_id":str(record.action_id),"binding_id":binding_key,"clip_name":clip_name,"pool_index":choice_index})
 if onset>=end_at-EPSILON:_cancelled_state+=1;return
 if _pending.size()>=maxi(0,max_queued_events):_stats.queue_budget_drops+=1;return
 var length:float=_stream_cache[path].get_length()
 var cue:Dictionary={"actor_id":actor,"character":str(record.character_id),"kind":"ordinary_state",
  "clip_name":clip_name,"binding_id":binding_key,"path":path,"start":onset,"end":onset+length,
  "clip_in_seconds":0.0,"volume_linear":float(row.raw_volume),"pitch_scale":1.0,"sample_duration":length,
  "generation":generation,"state_key":key,"state_token":token,"action_id":str(record.action_id),
  "state_name":str(record.state_name),"state_start":start,"phase_speed":speed,"raw_delay":float(row.raw_delay),
  "source_onset":source_onset,"sync_offset_seconds":onset-source_onset,
  "playback_classification":"source_waveform_with_explicit_autochess_state_adapter"}
 _pending.append(cue);_stats.scheduled_count+=1;_remember(_scheduled,cue)
func update_time(time:float,paused:bool=false)->void:
 if not is_finite(time) or time<_now-EPSILON:
  super.update_time(time,paused);return
 _prune_state_cues();super.update_time(time,paused)
func diagnostics()->Dictionary:
 var result:Dictionary=super.diagnostics()
 result.merge({"cancelled_state":_cancelled_state,"invalid_state_records":_invalid_states,"state_records":_states.size(),"choices":_choices.duplicate(true),"native_playback_parity_claimed":false,"adapter":"contact_anchored_fire_source_timed_reload_neutral_pitch"})
 return result
func _prune_state_cues()->void:
 for i in range(_pending.size()-1,-1,-1):
  var cue:Dictionary=_pending[i]
  if float(cue.start)>=float(_states.get(cue.get("state_key",""),{}).get("exit_at",INF))-EPSILON:
   _pending.remove_at(i);_cancelled_state+=1
 for i in range(_active.size()-1,-1,-1):
  var cue:Dictionary=_active[i]
  if float(cue.start)<float(_states.get(cue.get("state_key",""),{}).get("exit_at",INF))-EPSILON:continue
  if is_instance_valid(cue.get("player")):cue.player.stop();cue.player.stream_paused=false
  _active.remove_at(i);_cancelled_state+=1
func _choice_index(actor:int,action:String,binding:String,count:int)->int:
 var hash_context=HashingContext.new();hash_context.start(HashingContext.HASH_SHA256)
 hash_context.update(JSON.stringify([_battle_seed,actor,action,binding]).to_utf8_buffer())
 var digest:PackedByteArray=hash_context.finish()
 var value:int=(int(digest[0])<<24)|(int(digest[1])<<16)|(int(digest[2])<<8)|int(digest[3])
 return value%count
func _number(value:Variant)->bool:
 return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))
func _whole(value:Variant)->bool:
 return typeof(value)==TYPE_INT or (typeof(value)==TYPE_FLOAT and is_finite(value) and absf(value)<=9007199254740991.0 and value==floor(value))
func _text(value:Variant)->bool:
 return typeof(value) in [TYPE_STRING,TYPE_STRING_NAME]
func _issue(message:String)->void:
 _issues.append(message)
 while _issues.size()>maxi(0,max_diagnostic_records):_issues.pop_front()
func _load_manifest()->void:
 if _loaded:return
 _loaded=true
 var parsed:Variant=_read_manifest_data()
 if not parsed is Dictionary or parsed.get("schema_version",0)!=1 or not parsed.get("assets") is Dictionary or not parsed.get("bindings") is Array:
  _issue("invalid_ordinary_manifest");return
 for name in parsed.assets:
  var asset:Variant=parsed.assets[name]
  if not asset is Dictionary:continue
  if not _whole(asset.get("frames")) or float(asset.frames)<=0 or float(asset.frames)>10000000 or not _text(asset.get("path")) or not _text(asset.get("pcm_sha256")):
   _issue("invalid_ordinary_asset_metadata:"+str(name));continue
  var path:String=str(asset.path)
  if not path.begins_with("res://assets/audio/native-ordinary/") or not path.ends_with(".wav") or ".." in path or not ResourceLoader.exists(path):
   _issue("missing_ordinary_clip:"+path);continue
  var stream:Variant=_stream_cache.get(path)
  if stream==null:stream=load(path)
  if not stream is AudioStreamWAV or stream.loop_mode!=AudioStreamWAV.LOOP_DISABLED or stream.format!=AudioStreamWAV.FORMAT_16_BITS or stream.stereo or stream.mix_rate!=22050:
   _issue("unsupported_ordinary_clip:"+path);continue
  var hash_context=HashingContext.new();hash_context.start(HashingContext.HASH_SHA256);hash_context.update(stream.data)
  if hash_context.finish().hex_encode()!=str(asset.get("pcm_sha256","")) or stream.data.size()!=int(asset.get("frames",-1))*2:
   _issue("ordinary_pcm_mismatch:"+path);continue
  _stream_cache[path]=stream;_assets[str(name)]=asset.duplicate(true)
 var binding_counts:Dictionary={}
 for item in parsed.bindings:
  if item is Dictionary and _text(item.get("character")) and _text(item.get("state_name")):
   var key:String=str(item.character)+":"+str(item.state_name)
   binding_counts[key]=int(binding_counts.get(key,0))+1
 for item in parsed.bindings:
  if not item is Dictionary:continue
  var row:Dictionary=item
  if not _text(row.get("character")) or not _text(row.get("native_clip")) or row.get("state_name","") not in STATES:continue
  if not _number(row.get("raw_delay")) or float(row.raw_delay)<0 or not _number(row.get("raw_volume")) or float(row.raw_volume)<0:continue
  if not row.get("clips") is Array or row.clips.is_empty():continue
  var valid:bool=true
  for clip in row.clips:
   if not _text(clip) or not _assets.has(str(clip)):valid=false;break
  if not valid:_issue("missing_ordinary_pool:"+str(row.character));continue
  var key:String=str(row.character)+":"+str(row.state_name)
  if int(binding_counts.get(key,0))!=1:_issue("duplicate_ordinary_binding:"+key);continue
  _bindings[key]=row.duplicate(true);_manifest_events+=1

func _read_manifest_data()->Variant:
 var file=FileAccess.open(ORDINARY_MANIFEST,FileAccess.READ)
 if file==null:_issue("missing_ordinary_manifest");return null
 return JSON.parse_string(file.get_as_text())
