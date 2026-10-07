extends SceneTree
## Compare existing track bytes against the authenticated 11-clip checkpoint.
const OLD_SHA="69de7e72dddcea590362766c63d56f8e896b4c05911579696ce1bbf194b16aa8"
var failures:Array=[]
var checks:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label);printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func identity(clip:Animation,i:int)->String:return String(clip.track_get_path(i))+"|"+str(clip.track_get_type(i))
func run()->void:
 var args:PackedStringArray=OS.get_cmdline_user_args()
 if args.size()!=2:printerr("Expected checkpoint library and report JSON");quit(2);return
 ck(FileAccess.get_sha256(args[0])==OLD_SHA,"baseline native checkpoint is authenticated")
 if not failures.is_empty():quit(1);return
 var before:AnimationLibrary=ResourceLoader.load(args[0],"AnimationLibrary",ResourceLoader.CACHE_MODE_IGNORE)
 var after:AnimationLibrary=load("res://assets/characters/asuna/asuna-animation-library.res")
 var added:Array=[];var keys:=0;var tracks:=0
 ck(before.get_meta("rest_sha256")==after.get_meta("rest_sha256"),"authored local-rest signature unchanged")
 ck(before.get_animation_list().size()==11 and after.get_animation_list().size()==12,"exactly one native clip added")
 for name in before.get_animation_list():
  ck(after.has_animation(name),"previous clip retained")
  if not after.has_animation(name):continue
  var old:Animation=before.get_animation(name);var current:Animation=after.get_animation(name)
  ck(old.length==current.length and old.loop_mode==current.loop_mode and old.step==current.step,"clip timing and settings unchanged")
  for metadata in old.get_meta_list():ck(old.get_meta(metadata)==current.get_meta(metadata),"clip metadata unchanged")
  var current_tracks:Dictionary={}
  for i in current.get_track_count():current_tracks[identity(current,i)]=i
  for i in old.get_track_count():
   var key:String=identity(old,i)
   ck(current_tracks.has(key),"previous track retained")
   if not current_tracks.has(key):continue
   var j:int=current_tracks[key];current_tracks.erase(key)
   ck(old.track_get_interpolation_type(i)==current.track_get_interpolation_type(j) and old.track_is_enabled(i)==current.track_is_enabled(j) and old.track_get_interpolation_loop_wrap(i)==current.track_get_interpolation_loop_wrap(j),"track settings unchanged")
   ck(var_to_bytes(old.get("tracks/%d/keys"%i))==var_to_bytes(current.get("tracks/%d/keys"%j)),"serialized key bytes unchanged")
   keys+=old.track_get_key_count(i);tracks+=1
  for key in current_tracks:
   var i:int=current_tracks[key]
   ck(String(key)=="Asuna_Original/bone_root/Bip001/Skeleton3D:bone_skirtR00|1" and current.track_get_key_count(i)==2,"only audited skirt translation source track newly retained")
   added.append({"clip":String(name),"identity":key,"keys":current.track_get_key_count(i)})
 ck(keys==237054 and tracks==1672,"all original keys and tracks verified")
 ck(added.size()==11,"one newly retained channel per previous clip")
 var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"baseline_library_sha256":OLD_SHA,"current_library_sha256":FileAccess.get_sha256("res://assets/characters/asuna/asuna-animation-library.res"),"previous_clips":11,"unchanged_existing_tracks":tracks,"unchanged_existing_keys":keys,"added_tracks_in_previous_clips":added}
 FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("ASUNA PREVIOUS CLIPS CHECKS=",checks," FAILURES=",failures.size()," TRACKS=",tracks," KEYS=",keys)
 quit(1 if not failures.is_empty() else 0)
