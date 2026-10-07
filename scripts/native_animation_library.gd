extends RefCounted
## Optional offline-compiled native clips. Never parses glTF or changes imported resources.
const FIELDS=["animation_library_path","animation_library_manifest_path","animation_library_sha256","animation_library_manifest_sha256"]
static func configured(profile:Dictionary)->bool:
 for field in FIELDS:
  if profile.has(field):return true
 return false
static func digest(value:Variant)->String:
 var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(value))
 return hash.finish().hex_encode()
static func structure(library:AnimationLibrary)->Array:
 var result:Array=[]
 for name in library.get_animation_list():
  var clip:Animation=library.get_animation(name);var tracks:Array=[]
  for i in clip.get_track_count():
   tracks.append([String(clip.track_get_path(i)),clip.track_get_type(i),clip.track_get_interpolation_type(i),clip.track_is_enabled(i),clip.track_get_interpolation_loop_wrap(i)])
  result.append([String(name),clip.length,tracks])
 return result
static func rest_signature(model:Node3D)->String:
 var rows:Array=[]
 for node in model.find_children("*","Node3D",true,false):
  # Runtime-only PhysicalBoneSimulator3D children have per-instance names.
  # Include authored scene nodes only; excludes presentation root scale/yaw.
  if node.owner==null:continue
  rows.append([String(model.get_path_to(node)),node.transform])
  if node is Skeleton3D:
   for bone in node.get_bone_count():rows.append([String(model.get_path_to(node)),node.get_bone_name(bone),node.get_bone_parent(bone),node.get_bone_rest(bone)])
 return digest(rows)
static func target_error(player:AnimationPlayer,library:AnimationLibrary)->String:
 var base:Node=player.get_node_or_null(player.root_node)
 if base==null:return "AnimationPlayer root no longer resolves"
 for name in library.get_animation_list():
  var clip:Animation=library.get_animation(name)
  for i in clip.get_track_count():
   var path:NodePath=clip.track_get_path(i)
   var node:Node=base.get_node_or_null(NodePath(path.get_concatenated_names()))
   if node==null:return "Unresolved animation node: "+str(path)
   if path.get_subname_count()>0:
    if path.get_subname_count()!=1 or not node is Skeleton3D or node.find_bone(String(path.get_subname(0)))<0:return "Unresolved animation bone: "+str(path)
   elif not node is Node3D:return "Animation target is not Node3D: "+str(path)
 return ""
static func _error(message:String)->Dictionary:return {"error":"Native animation library: "+message}
static func select(profile:Dictionary,model:Node3D,player:AnimationPlayer)->Dictionary:
 for field in FIELDS:
  if not profile.get(field) is String or String(profile.get(field,"")).is_empty():return _error("missing "+field)
 if not profile.get("model_path") is String or not profile.get("source_glb_sha256") is String:return _error("missing source model/hash fields")
 if profile.get("normalize_durations",true):return _error("override requires source durations (normalize_durations=false)")
 var library_path:String=profile.animation_library_path
 var manifest_path:String=profile.animation_library_manifest_path
 if not library_path.ends_with(".res") or not manifest_path.ends_with(".res"):return _error("binary .res library and manifest required")
 for pair in [[library_path,profile.animation_library_sha256],[manifest_path,profile.animation_library_manifest_sha256]]:
  if not FileAccess.file_exists(pair[0]):return _error("missing resource: "+pair[0])
  if String(pair[1]).length()!=64 or FileAccess.get_sha256(pair[0])!=pair[1]:return _error("resource SHA256 mismatch: "+pair[0])
 var manifest:Resource=ResourceLoader.load(manifest_path,"",ResourceLoader.CACHE_MODE_IGNORE)
 var library:AnimationLibrary=ResourceLoader.load(library_path,"AnimationLibrary",ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
 if manifest==null or library==null:return _error("invalid manifest or AnimationLibrary resource")
 if not manifest.has_meta("contract"):return _error("invalid manifest schema")
 var contract:Variant=manifest.get_meta("contract")
 if not contract is Dictionary or contract.get("schema_version")!=1:return _error("invalid manifest schema")
 var source_hash:String=profile.get("source_glb_sha256","")
 if source_hash.length()!=64 or contract.get("source_glb_sha256")!=source_hash or library.get_meta("source_glb_sha256","")!=source_hash:return _error("declared source SHA256 mismatch")
 if contract.get("model_path")!=profile.get("model_path") or contract.get("library_sha256")!=profile.animation_library_sha256:return _error("manifest source/library identity mismatch")
 # PCK may contain only .glb.import/.scn. Build-time provenance validates raw GLB
 # bytes; runtime still authenticates both actual native resources and declared SHA.
 if FileAccess.file_exists(profile.model_path) and FileAccess.get_sha256(profile.model_path)!=source_hash:return _error("source GLB bytes SHA256 mismatch")
 if not contract.get("library_name") is String:return _error("invalid manifest library name")
 var names:PackedStringArray=player.get_animation_library_list()
 if names.size()!=1 or String(names[0])!=String(contract.get("library_name","")):return _error("imported library layout mismatch")
 var original:AnimationLibrary=player.get_animation_library(names[0])
 var signature:String=digest(structure(original))
 if signature!=contract.get("structure_sha256") or digest(structure(library))!=signature or library.get_meta("structure_sha256","")!=signature:return _error("clip/type/path structural signature mismatch")
 var rests:String=rest_signature(model)
 if rests!=contract.get("rest_sha256") or library.get_meta("rest_sha256","")!=rests:return _error("local rest signature mismatch")
 var error:String=target_error(player,library)
 if not error.is_empty():return _error(error)
 for name in profile.get("clips",{}).values():
  if not String(name).is_empty() and not library.has_animation(StringName(name)):return _error("missing declared clip: "+String(name))
 var clips:Variant=contract.get("clips")
 if not clips is Dictionary or clips.size()!=library.get_animation_list().size():return _error("clip metadata mismatch")
 var keys:int=0;var tracks:int=0
 for name in library.get_animation_list():
  var clip:Animation=library.get_animation(name)
  var row:Variant=clips.get(String(name))
  if not row is Dictionary or row.get("length")!=clip.length or row.get("tracks")!=clip.get_track_count() or not clip.has_meta("source_identity") or not clip.has_meta("source_extras") or row.get("source_identity")!=clip.get_meta("source_identity",{}) or row.get("source_extras")!=clip.get_meta("source_extras",{}):return _error("clip metadata mismatch: "+String(name))
  var count:int=0
  for i in clip.get_track_count():count+=clip.track_get_key_count(i)
  if count!=row.get("keys"):return _error("clip key count mismatch: "+String(name))
  keys+=count;tracks+=clip.get_track_count()
 if keys!=contract.get("keys") or tracks!=contract.get("tracks"):return _error("total key/track count mismatch")
 return {"error":"","library":library,"library_name":names[0],"contract":contract,"cache_identity":library_path+":"+profile.animation_library_sha256+":"+manifest_path+":"+profile.animation_library_manifest_sha256}
