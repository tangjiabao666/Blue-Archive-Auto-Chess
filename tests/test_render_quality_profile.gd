extends SceneTree
var checks:int=0
var failures:int=0
func ck(value:bool,message:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func run():
 # Removing the resolver or changing any presentation contract breaks this suite.
 ck(ResourceLoader.exists("res://core/render_quality_profile.gd"),"pure presentation quality resolver exists")
 if failures:quit(1);return
 var quality=load("res://core/render_quality_profile.gd")
 var desktop:Dictionary=quality.resolve({})
 ck(desktop.ok and desktop.values=={"rendering_scale":1.0,"max_fps":60,"reduce_smoke":false},"desktop default retains authored appearance with bounded 60 FPS scheduling")
 var mobile:Dictionary=quality.resolve({},true)
 ck(mobile.ok and mobile.values=={"rendering_scale":0.85,"max_fps":60,"reduce_smoke":false},"mobile defaults resolve to balanced presentation knobs")
 for preset in ["performance","balanced","high"]:
  var options:Dictionary={"quality_preset":preset,"render_scale":0.67,"fps_limit":90,"volume":0.35,"muted":true,"fullscreen":false,"reduce_smoke":true}
  var original:Dictionary=options.duplicate(true)
  var resolved:Dictionary=quality.resolve(options,true)
  ck(resolved.ok,"known preset resolves")
  ck(resolved.values.get("reduce_smoke",false),"explicit smoke reduction survives every quality preset")
  ck(not resolved.values.has("shadows_enabled") and not resolved.values.has("ambient_particle_density"),"profile cannot enable unauthored shadows or pretend an ambient layer exists")
  ck(resolved.values.rendering_scale==0.67 and resolved.values.max_fps==90,"independent user scale and cap override preset defaults")
  ck(options==original,"resolver never mutates settings")
  ck(resolved.values.size()==3,"resolver exposes only three implemented presentation knobs, no combat or animation settings")
 var native_120:Dictionary=quality.resolve({"quality_preset":"high","render_scale":1.0,"fps_limit":120},true)
 ck(native_120.ok and native_120.values=={"rendering_scale":1.0,"max_fps":120,"reduce_smoke":false},"native resolution and 120 FPS cap are available as explicit user targets")
 var partial:Dictionary=quality.resolve({"quality_preset":"performance"},true)
 ck(partial.ok and partial.values.rendering_scale==0.85 and partial.values.max_fps==60,"preset-only choice keeps explicit mobile defaults for independent knobs")
 for scale in [0.5,0.67,0.85,1.0]:
  for fps in [30,60,90,120]:
   var resolved:Dictionary=quality.resolve({"render_scale":scale,"fps_limit":fps},true)
   ck(resolved.ok and resolved.values.rendering_scale==scale and resolved.values.max_fps==fps,"resolver preserves every supported independent mobile scale and target")
 for bad in [{"quality_preset":"ultra"},{"quality_preset":false},{"render_scale":0.9},{"render_scale":"1.0"},{"render_scale":NAN},{"render_scale":INF},{"fps_limit":144},{"fps_limit":60.5},{"fps_limit":"60"},{"fps_limit":true},{"fps_limit":0}]:
  var rejected:Dictionary=quality.resolve(bad,true)
  ck(not rejected.ok and not rejected.has("values"),"malformed explicit options cannot become runtime profile")
 var first:Dictionary=quality.resolve({},true);first.values.rendering_scale=0.5
 ck(quality.resolve({},true).values.rendering_scale==0.85,"returned profiles never share mutable defaults")
 ck(quality.has_method("preset_defaults"),"menu can retrieve an explicit quality preset's recommended controls")
 if quality.has_method("preset_defaults"):
  for preset in ["performance","balanced","high"]:
   var recommended:Dictionary=quality.preset_defaults(preset)
   var expected:Dictionary={"performance":{"quality_preset":"performance","render_scale":0.67,"fps_limit":60},"balanced":{"quality_preset":"balanced","render_scale":0.85,"fps_limit":60},"high":{"quality_preset":"high","render_scale":1.0,"fps_limit":120}}[preset]
   ck(recommended.ok and recommended.values==expected,"menu receives complete recommended preset controls")
   var resolved:Dictionary=quality.resolve(recommended.values,true)
   ck(resolved.ok and resolved.values.rendering_scale==expected.render_scale and resolved.values.max_fps==expected.fps_limit and not resolved.values.reduce_smoke,"each recommended preset resolves without altering existing default smoke presentation")
   var manual_smoke:Dictionary=recommended.values.duplicate(true);manual_smoke["reduce_smoke"]=true
   ck(quality.resolve(manual_smoke,true).values.reduce_smoke,"manual smoke preference stays independent of every preset")
   recommended.values.render_scale=0.5
   ck(quality.preset_defaults(preset).values.render_scale==expected.render_scale,"mutating selected preset cannot corrupt future recommendations")
  var rejected:Dictionary=quality.preset_defaults("ultra")
  ck(not rejected.ok and not rejected.has("values"),"unknown preset produces no recommendation")
 print("RENDER_QUALITY_PROFILE ",checks," checks; ",failures," failures");quit(1 if failures else 0)
