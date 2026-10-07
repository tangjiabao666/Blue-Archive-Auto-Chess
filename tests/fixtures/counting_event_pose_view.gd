extends "res://scripts/unit_view.gd"
## Test-only counters; production presentation behavior is delegated unchanged.
static var event_advances:int=0
static var frame_advances:int=0
static var event_advance_us:int=0
var _in_frame_update:bool=false
func update_time(at:float,unit:Dictionary)->void:
 _in_frame_update=true
 super.update_time(at,unit)
 _in_frame_update=false
func advance_event_time(at:float,settle_idle:bool=false)->void:
 if _in_frame_update:
  frame_advances+=1;super.advance_event_time(at,settle_idle);return
 event_advances+=1
 var before:int=Time.get_ticks_usec()
 super.advance_event_time(at,settle_idle)
 event_advance_us+=Time.get_ticks_usec()-before
