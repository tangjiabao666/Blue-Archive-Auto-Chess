extends SceneTree
## Offline native compiler. Input is authenticated by prepare.py and source SHA.
const Guard=preload("res://scripts/native_animation_library.gd")
const PIN="a874892d8fe4fe952fe4ac0256797c73d82efa432f00eceb3e7e030375c5df07"
const PAYLOAD_SHA="44bcb71a4883c27a223db7181952b336d0ec1dcf802f7186630816afa89ccb01"
const LIBRARY_PATH="res://assets/characters/asuna/asuna-animation-library.res"
const MANIFEST_PATH="res://assets/characters/asuna/asuna-animation-manifest.res"
const KINDS={Animation.TYPE_POSITION_3D:"translation",Animation.TYPE_ROTATION_3D:"rotation",Animation.TYPE_SCALE_3D:"scale"}
func fail(message:String)->void:printerr("COMPILE FAILED: ",message);quit(1)
func _initialize()->void:call_deferred("run")
func value(row:Array,type:int)->Variant:
 return Quaternion(row[0],row[1],row[2],row[3]) if type==Animation.TYPE_ROTATION_3D else Vector3(row[0],row[1],row[2])
func array(v:Variant)->Array:
 return [v.x,v.y,v.z,v.w] if v is Quaternion else [v.x,v.y,v.z]
func error(a:Variant,b:Variant)->float:
 if a is Quaternion:
  var q:Quaternion=a.normalized();var r:Quaternion=b.normalized()
  var minus:float=sqrt(pow(q.x-r.x,2)+pow(q.y-r.y,2)+pow(q.z-r.z,2)+pow(q.w-r.w,2))
  var plus:float=sqrt(pow(q.x+r.x,2)+pow(q.y+r.y,2)+pow(q.z+r.z,2)+pow(q.w+r.w,2))
  return 4.0*asin(minf(1.0,minf(minus,plus)/2.0))
 return maxf(absf(a.x-b.x),maxf(absf(a.y-b.y),absf(a.z-b.z)))
func run()->void:
 var args:PackedStringArray=OS.get_cmdline_user_args()
 if args.size()!=2:fail("Expected prepared input JSON and receipt output JSON");return
 if not FileAccess.file_exists(args[0]) or FileAccess.get_sha256(args[0])!=PAYLOAD_SHA:fail("prepared payload SHA256 mismatch");return
 var input:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
 if not input is Dictionary or input.get("source_glb_sha256")!=PIN or FileAccess.get_sha256(input.get("model_path",""))!=PIN:fail("source provenance mismatch");return
 var scene:Node3D=load(input.model_path).instantiate();root.add_child(scene)
 var players:Array=scene.find_children("*","AnimationPlayer",true,false)
 if players.size()!=1:fail("expected one imported AnimationPlayer");return
 var player:AnimationPlayer=players[0]
 var names:PackedStringArray=player.get_animation_library_list()
 if names.size()!=1:fail("expected one imported library");return
 var original:AnimationLibrary=player.get_animation_library(names[0])
 if original.get_animation_list().size()!=input.clips.size():fail("clip names changed");return
 var signature:String=Guard.digest(Guard.structure(original));var rests:String=Guard.rest_signature(scene)
 var library:AnimationLibrary=AnimationLibrary.new()
 var contract:Dictionary={"schema_version":1,"prepared_payload_sha256":PAYLOAD_SHA,"godot_version":Engine.get_version_info().string,"model_path":input.model_path,"source_glb_sha256":PIN,"library_name":String(names[0]),"structure_sha256":signature,"rest_sha256":rests,"clips":{},"keys":0,"tracks":0,"matched_tracks":0,"source_keys":0,"generated_constant_tracks":0,"omitted_source_channels":0,"omitted_source_keys":0,"omitted_policy":"Audited approximately-default source channels remain omitted only while every source key is within rotation 0.001002 rad or vector 0.0000102 of imported local rest; generated channels retain original imported keys unchanged.","scope":"Native source-key restoration; not a visual, skin/world-bind, blend-transition or continuous-time parity certification."}
 var native_rest:Dictionary={}
 for node in scene.find_children("*","Node3D",true,false):
  native_rest[String(node.name)]=node.transform
  if node is Skeleton3D:
   for i in node.get_bone_count():native_rest[String(node.get_bone_name(i))]=node.get_bone_rest(i)
 for name in original.get_animation_list():
  if not input.clips.has(String(name)):fail("missing source clip: "+String(name));return
  var source:Dictionary=input.clips[String(name)]
  source.length=PackedFloat32Array([source.length])[0]
  for channel in source.channels.values():channel.times=PackedFloat32Array(channel.times)
  var clip:Animation=original.get_animation(name).duplicate(true)
  if clip.length!=source.length:fail("source/import duration mismatch: "+String(name));return
  clip.set_meta("source_extras",source.extras);clip.set_meta("source_identity",source.extras.unity_animation)
  var matched:Dictionary={};var samples:Array=[];var keys:int=0
  for i in clip.get_track_count():
   var type:int=clip.track_get_type(i)
   if not KINDS.has(type) or clip.track_get_interpolation_type(i)!=Animation.INTERPOLATION_LINEAR or not clip.track_is_enabled(i):fail("unsupported imported track settings");return
   var path:NodePath=clip.track_get_path(i)
   var leaf:String=String(path.get_subname(0)) if path.get_subname_count()>0 else String(path.get_name(path.get_name_count()-1))
   var identity:String=leaf+"|"+KINDS[type]
   if source.channels.has(identity):
    var channel:Dictionary=source.channels[identity]
    # track_insert_key merges approximately equal times. Set the native
    # serialized array directly so adjacent distinct float32 keys survive.
    var packed:PackedFloat32Array=PackedFloat32Array()
    for k in channel.times.size():
     packed.append(channel.times[k]);packed.append(1.0)
     packed.append_array(PackedFloat32Array(channel.values[k]))
    clip.set("tracks/%d/keys"%i,packed)
    if clip.track_get_key_count(i)!=channel.times.size():fail("native serialization lost source keys");return
    for k in channel.times.size():
     if clip.track_get_key_time(i,k)!=channel.times[k] or clip.track_get_key_value(i,k)!=value(channel.values[k],type):fail("native serialization changed source key");return
    for k in [0,channel.times.size()/2,channel.times.size()-1]:samples.append([i,type,channel.times[int(k)],channel.values[int(k)]])
    matched[identity]=true;contract.matched_tracks+=1;contract.source_keys+=channel.times.size()
   else:
    if clip.track_get_key_count(i)!=1:fail("generated imported channel is not constant");return
    var expected:Variant=value(input.nodes[leaf][KINDS[type]],type)
    if error(clip.track_get_key_value(i,0),expected)>(0.001002 if type==2 else 0.0000102):fail("generated constant differs from source rest");return
    samples.append([i,type,0.0,array(clip.track_get_key_value(i,0))]);contract.generated_constant_tracks+=1
   keys+=clip.track_get_key_count(i)
  for identity in source.channels:
   if matched.has(identity):continue
   var channel:Dictionary=source.channels[identity]
   if not native_rest.has(channel.node):fail("omitted source target does not resolve: "+channel.node);return
   var t:Transform3D=native_rest[channel.node]
   var expected:Variant=t.basis.get_rotation_quaternion() if channel.kind=="rotation" else t.origin if channel.kind=="translation" else t.basis.get_scale()
   var type:int=2 if channel.kind=="rotation" else 1
   for row in channel["values"]:
    if error(value(row,type),expected)>(0.001002 if type==2 else 0.0000102):fail("omitted source channel changed from audited local rest: "+identity);return
   contract.omitted_source_channels+=1;contract.omitted_source_keys+=channel.times.size()
  library.add_animation(name,clip)
  contract.clips[String(name)]={"length":clip.length,"tracks":clip.get_track_count(),"keys":keys,"source_identity":source.extras.unity_animation,"source_extras":source.extras,"samples":samples}
  contract.keys+=keys;contract.tracks+=clip.get_track_count()
 # Measured from the audited 12-clip importer topology; skirt translation adds
 # one two-key source track to each of the previous 11 clips.
 if contract.clips.size()!=12 or contract.tracks!=1836 or contract.keys!=262988 or contract.matched_tracks!=1818 or contract.source_keys!=262970 or contract.generated_constant_tracks!=18 or contract.omitted_source_channels!=2522 or contract.omitted_source_keys!=39345:fail("restoration counts differ from the audited source");return
 if Guard.digest(Guard.structure(library))!=signature:fail("compiler changed imported track structure");return
 var target_error:String=Guard.target_error(player,library)
 if not target_error.is_empty():fail(target_error);return
 for key in ["source_glb_sha256","structure_sha256","rest_sha256"]:library.set_meta(key,contract[key])
 if ResourceSaver.save(library,LIBRARY_PATH,ResourceSaver.FLAG_COMPRESS)!=OK:fail("cannot save native library");return
 contract.library_sha256=FileAccess.get_sha256(LIBRARY_PATH)
 var manifest:Resource=Resource.new();manifest.set_meta("contract",contract)
 if ResourceSaver.save(manifest,MANIFEST_PATH,ResourceSaver.FLAG_COMPRESS)!=OK:fail("cannot save native manifest");return
 var receipt:Dictionary={"animation_library_path":LIBRARY_PATH,"animation_library_manifest_path":MANIFEST_PATH,"animation_library_sha256":contract.library_sha256,"animation_library_manifest_sha256":FileAccess.get_sha256(MANIFEST_PATH),"source_glb_sha256":PIN,"prepared_payload_sha256":PAYLOAD_SHA,"matched_tracks":contract.matched_tracks,"source_keys":contract.source_keys,"generated_constant_tracks":contract.generated_constant_tracks,"tracks":contract.tracks,"keys":contract.keys,"omitted_source_channels":contract.omitted_source_channels,"omitted_source_keys":contract.omitted_source_keys,"structure_sha256":signature,"rest_sha256":rests}
 FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
 scene.free();print("ASUNA NATIVE COMPILER ",JSON.stringify(receipt));quit()
