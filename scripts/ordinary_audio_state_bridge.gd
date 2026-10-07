extends RefCounted
## Presentation-only ledger. It observes native selection, never drives animation.
signal ordinary_audio_state(record:Dictionary)
const MAX_SEEN_STATES:=8192
const QUALIFIED_STATES:Dictionary={"attack_fire":"Base Layer.Normal.AttackIng","reload":"Base Layer.Normal.Reload"}
var _actor_id:=-1
var _character_id:=""
var _generation:=-1
var _active:Dictionary={}
var _seen:Dictionary={}

func reset(actor_id:int,character_id:String,generation:int,at:float)->void:
 finish(at,"reset")
 _actor_id=actor_id;_character_id=character_id;_generation=generation
 _seen.clear()

static func action_identity(event:Dictionary)->String:
 var event_id:String=str(event.get("event_id",""))
 # Core event IDs are authoritative. Legacy packets have one action/type/tick.
 return event_id if not event_id.is_empty() else JSON.stringify([event.get("actor_id",-1),event.get("type",""),event.get("tick",0)])

func selected(action_id:String,phase:String,native_clip:String,started_at:float,source_offset:float,speed:float,planned_end:float,effective_at:float)->void:
 var state_name:String=QUALIFIED_STATES.get(phase,"")
 var token:String=JSON.stringify([_generation,_actor_id,action_id,state_name])
 # Duplicate delivery can force the same clip again in legacy presentation.
 # It must not replace/cancel an existing sound or resurrect a finished state.
 if not state_name.is_empty() and _seen.has(token):return
 finish(effective_at,"death" if phase=="death" else "replaced")
 if state_name.is_empty() or action_id.is_empty() or _character_id.is_empty() or _generation<0 or _actor_id<0:return
 if not is_finite(started_at) or not is_finite(planned_end) or not is_finite(speed) or not is_finite(source_offset) or speed<=0.0 or planned_end<=started_at:return
 # Fail closed at the lifetime bound instead of evicting old identities that
 # could then be replayed. reset starts a fresh ledger even for reused numbers.
 if _seen.size()>=MAX_SEEN_STATES:return
 _seen[token]=true
 _active={"type":"enter","actor_id":_actor_id,"character_id":_character_id,"generation":_generation,"token":token,"action_id":action_id,"state_name":state_name,"native_clip":native_clip,"start_time":started_at,"source_offset":source_offset,"speed":speed,"planned_end_time":planned_end}
 ordinary_audio_state.emit(_active.duplicate())

func advance(at:float)->void:
 if not _active.is_empty() and at>=float(_active.planned_end_time):finish(float(_active.planned_end_time),"phase_end")

func finish(at:float,reason:String)->void:
 if _active.is_empty():return
 var ended_at:float=minf(at,float(_active.planned_end_time))
 var record:Dictionary={"type":"exit","actor_id":_actor_id,"generation":_generation,"token":_active.token,"at":ended_at,"reason":reason if at<float(_active.planned_end_time) else "phase_end"}
 _active={}
 ordinary_audio_state.emit(record)
