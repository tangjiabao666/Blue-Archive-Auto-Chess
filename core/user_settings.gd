extends RefCounted
## Presentation preferences only; never changes match rules or source quality.
const VERSION:int=1
const DEFAULT_PATH:String="user://settings.cfg"
const DEFAULTS:Dictionary={"volume":1.0,"muted":false,"fullscreen":false,"reduce_smoke":false}
# Quality fields are optional in version one. Keep legacy dictionaries unchanged,
# and resolve platform defaults explicitly at the presentation boundary.
const QUALITY_DEFAULTS_DESKTOP:Dictionary={"quality_preset":"high","render_scale":1.0,"fps_limit":60}
const QUALITY_DEFAULTS_MOBILE:Dictionary={"quality_preset":"balanced","render_scale":0.85,"fps_limit":60}
const QUALITY_PRESETS:Array=["performance","balanced","high"]
const RENDER_SCALES:Array=[0.5,0.67,0.85,1.0]
const FPS_LIMITS:Array=[30,60,90,120]
static func with_quality_defaults(values:Dictionary,mobile:bool=false)->Dictionary:
 var result:Dictionary=values.duplicate(true)
 var defaults:Dictionary=QUALITY_DEFAULTS_MOBILE if mobile else QUALITY_DEFAULTS_DESKTOP
 for key in defaults:
  if not result.has(key):result[key]=defaults[key]
 return result
static func validate(values:Dictionary,mobile:bool=false)->Dictionary:
 if not values.has_all(["volume","muted","fullscreen"]):return {"ok":false,"error":"设置字段不完整"}
 var volume=values.volume
 if not(volume is float or volume is int) or not is_finite(float(volume)) or float(volume)<0.0 or float(volume)>1.0:return {"ok":false,"error":"音量必须在 0 到 100% 之间"}
 # Older version-one settings keep the original authored smoke presentation.
 var reduce_smoke=values.get("reduce_smoke",false)
 if not values.muted is bool or not values.fullscreen is bool or not reduce_smoke is bool:return {"ok":false,"error":"设置格式无效"}
 var normalized:Dictionary={"volume":float(volume),"muted":values.muted,"fullscreen":values.fullscreen,"reduce_smoke":reduce_smoke}
 if values.has("quality_preset"):
  var preset=values.quality_preset
  if not preset is String or not QUALITY_PRESETS.has(preset):return {"ok":false,"error":"画质档位无效"}
  normalized["quality_preset"]=preset
 if values.has("render_scale"):
  var scale=values.render_scale
  if not(scale is float or scale is int) or not is_finite(float(scale)) or not RENDER_SCALES.has(float(scale)):return {"ok":false,"error":"渲染比例无效"}
  normalized["render_scale"]=float(scale)
 if values.has("fps_limit"):
  var fps=values.fps_limit
  if not fps is int or not(FPS_LIMITS.has(fps) or (fps==0 and not mobile)):return {"ok":false,"error":"帧率上限无效"}
  normalized["fps_limit"]=fps
 return {"ok":true,"error":"","values":normalized}
static func read_settings(path:String=DEFAULT_PATH,mobile:bool=false)->Dictionary:
 if not FileAccess.file_exists(path):return {"ok":true,"error":"","exists":false,"values":DEFAULTS.duplicate()}
 var config=ConfigFile.new();var error:int=config.load(path)
 if error!=OK or config.get_value("settings","version",0)!=VERSION:
  return {"ok":false,"error":"设置文件损坏或版本不兼容，已使用默认设置","exists":true,"values":DEFAULTS.duplicate()}
 var values:Dictionary={}
 for key in DEFAULTS:values[key]=config.get_value("settings",key,DEFAULTS[key])
 for key in QUALITY_DEFAULTS_DESKTOP:
  if config.has_section_key("settings",key):values[key]=config.get_value("settings",key)
 var result:Dictionary=validate(values,mobile)
 result["exists"]=true
 if not result.ok:result["values"]=DEFAULTS.duplicate()
 return result
static func write_settings(values:Dictionary,path:String=DEFAULT_PATH,mobile:bool=false)->Dictionary:
 var result:Dictionary=validate(values,mobile)
 if not result.ok:return result
 var config=ConfigFile.new();config.set_value("settings","version",VERSION)
 for key in result.values:config.set_value("settings",key,result.values[key])
 var temporary:String=path+".tmp"
 var error:int=config.save(temporary)
 if error!=OK:return {"ok":false,"error":"无法写入设置文件（%d）"%error}
 # Rename only a successfully parsed temporary file; previous settings remain
 # intact when validation or writing fails. No match-save file is touched.
 var checked:Dictionary=read_settings(temporary,mobile)
 if not checked.ok or checked.values!=result.values:return {"ok":false,"error":"设置写入校验失败"}
 error=DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))
 if error!=OK:return {"ok":false,"error":"无法替换设置文件（%d）"%error}
 return {"ok":true,"error":"","values":result.values}
