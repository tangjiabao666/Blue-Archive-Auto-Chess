extends RefCounted
## Pure presentation policy. Frame targets are ceilings, not guarantees.
## This does not change combat, telegraphs, animation, lights or source assets.
const UserSettings=preload("res://core/user_settings.gd")
const PRESET_DEFAULTS:Dictionary={
 "performance":{"quality_preset":"performance","render_scale":0.67,"fps_limit":60},
 "balanced":{"quality_preset":"balanced","render_scale":0.85,"fps_limit":60},
 "high":{"quality_preset":"high","render_scale":1.0,"fps_limit":120}}
# Explicit menu preset selection may replace the independent controls with these
# recommendations. Smoke reduction remains a separate manual preference.
# Merely loading preferences must preserve the user's choices.
static func preset_defaults(preset:String)->Dictionary:
 if not PRESET_DEFAULTS.has(preset):return {"ok":false,"error":"画质档位无效"}
 return {"ok":true,"error":"","values":PRESET_DEFAULTS[preset].duplicate(true)}
static func resolve(preferences:Dictionary,mobile:bool=false)->Dictionary:
 var candidate:Dictionary=UserSettings.DEFAULTS.duplicate()
 candidate.merge(preferences,true)
 var checked:Dictionary=UserSettings.validate(candidate,mobile)
 if not checked.ok:return checked
 var values:Dictionary=UserSettings.with_quality_defaults(checked.values,mobile)
 return {"ok":true,"error":"","values":{
  "rendering_scale":values.render_scale,
  "max_fps":values.fps_limit,
  "reduce_smoke":values.reduce_smoke}}
