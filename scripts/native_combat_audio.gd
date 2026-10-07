extends Node
## Explicit battle-clock adapter for verified original single-clip skill SFX.
## Own this node in GameApp, never BattleStage/render warmup. No autonomous process.
## Natural WAV end, global non-spatial output, death cancellation and budget drops
## are adapter policies; native mixer, attenuation and interruption are unresolved.
const MANIFEST="res://data/audio/native-skill-sfx.json"
const TICK_SECONDS=0.05
const EPSILON=0.0000001
static var _stream_cache:Dictionary={}
var output_enabled:bool=true:
 set(value):
  output_enabled=value
  if not value:
   for voice in _active:
    if is_instance_valid(voice.get("player")):voice.player.stop()
    voice.player=null
var max_voices:int=24
var max_queued_events:int=256
var max_seen_actions:int=8192
var max_diagnostic_records:int=256
var generation:int=-1
var _bindings:Dictionary={}
var _characters:Dictionary={}
var _dead_at:Dictionary={}
var _seen_actions:Dictionary={}
var _seen_ids:Dictionary={}
var _pending:Array=[]
var _active:Array=[]
var _players:Array=[]
var _scheduled:Array=[]
var _played:Array=[]
var _issues:Array=[]
var _now:float=0.0
var _paused:bool=false
var _draining:bool=false
var _tail_end:float=0.0
var _loaded:bool=false
var _manifest_events:int=0
var _stats:Dictionary={}

func _init()->void:
 set_process(false);set_physics_process(false)
 _clear_stats()

func _exit_tree()->void:
 reset(generation)

func begin_roster(units:Array,new_generation:int)->void:
 reset(new_generation)
 _load_manifest()
 for unit in units:
  var actor:int=int(unit.get("id",-1))
  if actor<0:continue
  _characters[actor]=str(unit.get("character_id",""))
  if float(unit.get("hp",1))<=0:_dead_at[actor]=0.0

func reset(new_generation:int)->void:
 # Always flush, even when a newly-created clock reuses a generation number.
 for player in _players:
  if is_instance_valid(player):player.stop();player.stream_paused=false
 generation=new_generation
 _characters.clear();_dead_at.clear();_seen_actions.clear();_seen_ids.clear()
 _pending.clear();_active.clear();_scheduled.clear();_played.clear()
 _now=0.0;_paused=false;_draining=false;_tail_end=0.0;_clear_stats();_enforce_voice_budget()

func consume(event:Dictionary)->void:
 if _draining:return
 if int(event.get("generation",generation))!=generation:_stats.stale_events+=1;return
 var actor:int=int(event.get("actor_id",-1))
 if not _characters.has(actor):return
 var tick:float=float(event.get("tick",-1))
 if not is_finite(tick) or tick<0:return
 var at:float=tick*TICK_SECONDS
 var type:String=str(event.get("type",""))
 if type=="action_cancelled":
  var cancel_id:String=str(event.get("event_id",""))
  if not cancel_id.is_empty() and _seen_ids.has(cancel_id):return
  if not cancel_id.is_empty():_seen_ids[cancel_id]=true
  for cues in [_pending,_active]:
   for cue in cues:
    if int(cue.actor_id)!=actor or str(cue.kind)!="basic" or not event.get("abilities",[]).has("basic"):continue
    if int(cue.cast_start_tick)>int(tick):continue
    cue["cancelled_at"]=minf(at,float(cue.get("cancelled_at",INF)))
  _prune_active();_prune_cancelled_pending();return
 if type=="death":
  _dead_at[actor]=minf(float(_dead_at.get(actor,INF)),at)
  _prune_active();_prune_dead_pending();return
 var kind:String=str(event.get("ability",""))
 if not ((type=="skill" and kind=="ex") or (type=="basic" and kind=="basic")):return
 if event.get("component","")=="echo":return
 if at>=float(_dead_at.get(actor,INF)):_stats.cancelled_death+=1;return
 var rows:Array=_bindings.get(str(_characters[actor])+":"+kind,[])
 if rows.is_empty():return
 var identity:String="%d:%s:%s"%[actor,str(tick),kind]
 var event_id:String=str(event.get("event_id",""))
 if _seen_actions.has(identity) or (not event_id.is_empty() and _seen_ids.has(event_id)):_stats.duplicates+=1;return
 # Do not evict dedup entries: eviction would allow old packets to replay.
 if _seen_actions.size()>=maxi(0,max_seen_actions):_stats.seen_budget_drops+=1;return
 _seen_actions[identity]=true
 if not event_id.is_empty():_seen_ids[event_id]=true
 for row in rows:
  if _pending.size()>=maxi(0,max_queued_events):_stats.queue_budget_drops+=1;continue
  var start:float=at+float(row.startSeconds)+float(row.delaySeconds)
  var rate:float=float(row.pitch)*float(row.timeScale)
  var length:float=_stream_cache[str(row.resourcePath)].get_length()
  var cue:Dictionary={"actor_id":actor,"character":str(_characters[actor]),"kind":kind,
   "clip_name":str(row.clipName),"binding_id":str(row.bindingId),"path":str(row.resourcePath),
   "start":start,"end":start+(length-float(row.clipInSeconds))/rate,
   "clip_in_seconds":float(row.clipInSeconds),"volume_linear":float(row.volumeLinear),
   "pitch_scale":rate,"sample_duration":length,"generation":generation,"cast_start_tick":int(event.get("cast_start_tick",tick))}
  _pending.append(cue);_stats.scheduled_count+=1
  _remember(_scheduled,cue)

func begin_tail_drain(cutoff:float,max_tail_seconds:float=0.8)->void:
 if _draining or not is_finite(cutoff) or not is_finite(max_tail_seconds) or cutoff<_now-EPSILON:return
 _draining=true;_tail_end=cutoff+clampf(max_tail_seconds,0.0,2.0)
 # Only already-started one-shots survive; no reload/drop cue begins postcombat.
 _pending.clear()
 for voice in _active:voice.end=minf(float(voice.end),_tail_end)
 _prune_active()

func update_time(time:float,paused:bool=false)->void:
 if not is_finite(time):return
 if time<_now-EPSILON:_stats.rewinds_rejected+=1;return
 var was_paused:bool=_paused
 _paused=paused
 for voice in _active:
  if is_instance_valid(voice.get("player")):voice.player.stream_paused=paused
 if paused:return
 _now=time
 _prune_active();_prune_cancelled_pending();_enforce_voice_budget()
 if was_paused:
  for voice in _active:
   if is_instance_valid(voice.get("player")):
    voice.player.seek(_sample_position(voice,time))
 _pending.sort_custom(func(a,b):
  if not is_equal_approx(float(a.start),float(b.start)):return float(a.start)<float(b.start)
  if int(a.actor_id)!=int(b.actor_id):return int(a.actor_id)<int(b.actor_id)
  return str(a.binding_id)<str(b.binding_id))
 var later:Array=[]
 for cue in _pending:
  if _now>=float(_dead_at.get(int(cue.actor_id),INF)):
   _stats.cancelled_death+=1;continue
  if float(cue.start)>time+EPSILON:later.append(cue);continue
  if time>=float(cue.end)-EPSILON:_stats.skipped_ended+=1;continue
  if _active.size()>=maxi(0,max_voices):_stats.voice_budget_drops+=1;continue
  _start_cue(cue)
 _pending=later

func diagnostics()->Dictionary:
 var result:Dictionary=_stats.duplicate(true)
 result.merge({"generation":generation,"time":_now,"paused":_paused,
  "output_enabled":output_enabled,"manifest_events":_manifest_events,"tail_draining":_draining,"tail_end":_tail_end,
  "queued_events":_pending.size(),"active_voices":_active.size(),"player_nodes":_players.size(),
  "seen_actions":_seen_actions.size(),"scheduled":_scheduled.duplicate(true),
  "played":_played.duplicate(true),"issues":_issues.duplicate(true)})
 return result

func _start_cue(cue:Dictionary)->void:
 var voice:Dictionary=cue.duplicate(true)
 var player:AudioStreamPlayer=null
 if output_enabled:
  player=_acquire_player()
  if player==null:_stats.voice_budget_drops+=1;return
  player.stream=_stream_cache[str(cue.path)]
  player.pitch_scale=float(cue.pitch_scale);player.volume_linear=float(cue.volume_linear)
  player.stream_paused=false;player.play(_sample_position(cue,_now))
 voice.player=player;_active.append(voice)
 var record:Dictionary=cue.duplicate(true)
 record.seek_seconds=_sample_position(cue,_now);record.started_at=_now
 _stats.played_count+=1;_remember(_played,record)

func _sample_position(cue:Dictionary,time:float)->float:
 return float(cue.clip_in_seconds)+maxf(0.0,time-float(cue.start))*float(cue.pitch_scale)

func _prune_active()->void:
 for i in range(_active.size()-1,-1,-1):
  var voice:Dictionary=_active[i]
  var dead:bool=_now>=float(_dead_at.get(int(voice.actor_id),INF))
  var cancelled:bool=_now>=float(voice.get("cancelled_at",INF))-EPSILON
  if not dead and not cancelled and _now<float(voice.end)-EPSILON:continue
  if is_instance_valid(voice.get("player")):voice.player.stop();voice.player.stream_paused=false
  if dead:_stats.cancelled_death+=1
  elif cancelled:_stats.cancelled_action+=1
  _active.remove_at(i)

func _prune_cancelled_pending()->void:
 for i in range(_pending.size()-1,-1,-1):
  var cue:Dictionary=_pending[i]
  # Future onsets after the cutoff can never play; release their capacity now.
  # Keep earlier onsets until the clock actually reaches their cancellation.
  if maxf(_now,float(cue.start))>=float(cue.get("cancelled_at",INF))-EPSILON:
   _pending.remove_at(i);_stats.cancelled_action+=1

func _prune_dead_pending()->void:
 for i in range(_pending.size()-1,-1,-1):
  if _now>=float(_dead_at.get(int(_pending[i].actor_id),INF)):
   _pending.remove_at(i);_stats.cancelled_death+=1

func _acquire_player()->AudioStreamPlayer:
 for player in _players:
  var busy:bool=false
  for voice in _active:
   if voice.get("player")==player:busy=true;break
  if not busy:return player
 if _players.size()>=maxi(0,max_voices):return null
 var player:=AudioStreamPlayer.new()
 player.name="NativeSkillVoice"+str(_players.size());player.max_polyphony=1
 add_child(player);_players.append(player)
 return player

func _enforce_voice_budget()->void:
 var limit:int=maxi(0,max_voices)
 while _active.size()>limit:
  var voice:Dictionary=_active.pop_back()
  if is_instance_valid(voice.get("player")):voice.player.stop()
  _stats.voice_budget_drops+=1
 for i in range(_players.size()-1,-1,-1):
  if _players.size()<=limit:break
  var player:AudioStreamPlayer=_players[i]
  if _active.any(func(v):return v.get("player")==player):continue
  player.free();_players.remove_at(i)

func _remember(records:Array,record:Dictionary)->void:
 records.append(record.duplicate(true))
 while records.size()>maxi(0,max_diagnostic_records):records.pop_front()

func _clear_stats()->void:
 _stats={"scheduled_count":0,"played_count":0,"duplicates":0,"stale_events":0,
  "skipped_ended":0,"cancelled_death":0,"cancelled_action":0,"queue_budget_drops":0,
  "voice_budget_drops":0,"seen_budget_drops":0,"rewinds_rejected":0}

func _load_manifest()->void:
 if _loaded:return
 _loaded=true
 var file:=FileAccess.open(MANIFEST,FileAccess.READ)
 if file==null:_issues.append("missing_native_audio_manifest");return
 var parsed=JSON.parse_string(file.get_as_text())
 if not parsed is Dictionary:_issues.append("invalid_native_audio_manifest");return
 for row in parsed.get("records",[]):
  if not row is Dictionary:continue
  var kind:String=str(row.get("timelineKind",""))
  if kind not in ["ex","basic"] or not row.get("currentSimSelectable",false):continue
  var data:Dictionary=row.get("nativeAudioData",{})
  if row.get("muted",true) or row.get("loop",true) or data.get("AudioClips",[]).size()!=1:continue
  if float(row.get("pitch",0))<=0:continue
  # Only source-verified timeScale=1 / Delay=0 semantics ship in this subset.
  if float(row.get("timeScale",0))!=1.0 or float(row.get("delaySeconds",-1))!=0.0:continue
  if float(data.get("RandomPitchMin",0))!=0 or float(data.get("RandomPitchMax",0))!=0:continue
  if float(row.get("clipInSeconds",-1))<0 or float(row.get("volumeLinear",-1))<0:continue
  var path:String=str(row.get("resourcePath",""))
  if not path.begins_with("res://assets/audio/native-skills/") or not ResourceLoader.exists(path):
   _issues.append("missing_packaged_clip:"+path);continue
  if not _stream_cache.has(path):
   var stream=load(path)
   if not stream is AudioStreamWAV or stream.loop_mode!=AudioStreamWAV.LOOP_DISABLED:
    _issues.append("unsupported_or_looping_clip:"+path);continue
   _stream_cache[path]=stream
  if float(row.clipInSeconds)>=_stream_cache[path].get_length():continue
  var key:String=str(row.get("character",""))+":"+kind
  if not _bindings.has(key):_bindings[key]=[]
  _bindings[key].append(row.duplicate(true));_manifest_events+=1
