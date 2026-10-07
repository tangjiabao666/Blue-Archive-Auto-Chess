extends RefCounted
## Versioned combat adaptation; original character/skill data is not modified.
static func options(profile:int)->Dictionary:
 var value:Dictionary={'overtime_enabled':true,'overtime_start_seconds':75.0,'overtime_ramp_seconds':30.0,'overtime_min_sustain_multiplier':0.2}
 if profile in [1,2]:value.max_ticks=3000;value.tactical_damage_scale=0.12
 if profile==3:
  value.max_ticks=1800;value.tactical_damage_scale=0.40;value.overtime_start_seconds=60.0;value.overtime_ramp_seconds=10.0;value.timeout_total_hp=true
 return value
