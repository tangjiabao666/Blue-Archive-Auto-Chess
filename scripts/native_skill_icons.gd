extends RefCounted
# Verified historical mirror glyphs. Selection never manufactures combat state.
static var _manifest:Dictionary={}
static var _textures:Dictionary={}
func _init()->void:
 if _manifest.is_empty():
  var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/skill-icons.json"))
  if parsed is Dictionary:_manifest=parsed
func skill_key(character:String,slot:String)->String:
 return str(_manifest.get("characters",{}).get(character,{}).get(slot,""))
func effect_key(effect:Dictionary,buffs:Dictionary,charges:int)->String:
 var id:String=str(effect.get("id",""))
 var semantics:Dictionary=_manifest.get("statusSemanticMap",{})
 if id=="charge":
  return str(semantics.get("arisCharge",{}).get("stateAssets",{}).get(str(charges),""))
 if id in ["shield","stun","taunt"]:return str(semantics.get(id,{}).get("assetKey",""))
 var buff:Dictionary=buffs.get(id,{})
 if buff.is_empty() or float(buff.get("fraction",0))<0:return ""
 var effect_mapping:Dictionary=_manifest.get("statusEffectMap",{}).get(id,{})
 if not effect_mapping.is_empty() and str(effect_mapping.get("stat",""))==str(buff.get("stat","")):
  return str(effect_mapping.get("assetKey",""))
 return str(semantics.get(str(buff.get("stat","")),{}).get("assetKey",""))
func texture(key:String)->Texture2D:
 if key.is_empty():return null
 if _textures.has(key):return _textures[key]
 var path:String=str(_manifest.get("assets",{}).get(key,{}).get("path",""))
 if path.is_empty():return null
 var loaded:Variant=load(path)
 if loaded is Texture2D:_textures[key]=loaded;return loaded
 return null
func region(key:String)->Rect2:
 var bounds:Array=_manifest.get("assets",{}).get(key,{}).get("alphaBounds",[])
 if bounds.size()!=4:return Rect2()
 return Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2])-float(bounds[0]),float(bounds[3])-float(bounds[1]))
