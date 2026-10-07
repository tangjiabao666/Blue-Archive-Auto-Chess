extends SceneTree
## Consumer-level failures must never silently select fixed-60 imported clips.
const Guard=preload("res://scripts/native_animation_library.gd")
var failures:=0
var checks:=0
var profile:Dictionary
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func view_for(p:Dictionary):
 var view=load("res://scripts/unit_view.gd").new();root.add_child(view)
 view.setup({"id":91,"character_id":"asuna","team":0,"cell":Vector2.ZERO,"range":3.0,"attack_ticks":60,"presentation":p},{},7)
 return view
func fail_closed(p:Dictionary,label:String)->void:
 var view=view_for(p)
 ck(view.player==null,label+" fails closed")
 ck(not view.diagnostics().warnings.is_empty(),label+" reports warning")
 ck(view.current_clip==&"",label+" starts no clip")
 view.free()
func patch(field:String,v:Variant,label:String)->void:
 var changed:Dictionary=profile.duplicate(true);changed[field]=v;fail_closed(changed,label)
func saved_manifest(contract:Variant,name:String)->Dictionary:
 var resource:Resource=Resource.new()
 if contract!=null:resource.set_meta("contract",contract)
 var path:String="user://asuna-test-"+name+".res";ck(ResourceSaver.save(resource,path)==OK,"fixture saves "+name)
 var changed:Dictionary=profile.duplicate(true);changed.animation_library_manifest_path=path;changed.animation_library_manifest_sha256=FileAccess.get_sha256(path)
 return changed
func death_event_fixture(p:Dictionary)->void:
 var view=view_for(p)
 ck(p.clips.get("death","")=="Asuna_Original_Vital_Death","death maps to exact Asuna source clip")
 ck(view.player!=null,"death fixture selects authenticated library")
 if view.player==null:view.free();return
 var event:Dictionary={"type":"death","actor_id":91,"generation":7,"tick":60,"event_id":"asuna-native-death"}
 view.consume(event)
 ck(view.is_dead and not view.is_moving,"death event owns actor lifecycle")
 ck(view.current_clip==&"Asuna_Original_Vital_Death","death event selects Asuna clip instead of Rio fallback")
 ck(view.player.current_animation=="Asuna_Original_Vital_Death","actual player selects Asuna death")
 ck(view.diagnostics().warnings.is_empty(),"death event emits no missing native clip warning")
 if view.player.has_animation("Asuna_Original_Vital_Death"):
  var clip:Animation=view.player.get_animation("Asuna_Original_Vital_Death")
  ck(clip.length==1.9666668176651 and clip.loop_mode==Animation.LOOP_NONE,"source death duration and nonloop policy")
  ck(clip.get_meta("source_identity",{}).get("path_id","")=="1009064993132161451","death retains exact source identity")
  view.advance_event_time(60*view.TICK_SECONDS+0.5)
  ck(absf(view.player.current_animation_position-0.5)<0.00001,"death advances at unnormalized source speed")
  view.consume(event)
  ck(absf(view.player.current_animation_position-0.5)<0.00001,"duplicate death event does not restart playback")
  view.consume({"type":"death","actor_id":91,"generation":6,"tick":90,"event_id":"stale-death"})
  ck(absf(view.player.current_animation_position-0.5)<0.00001,"stale generation death cannot restart current clip")
  view.advance_event_time(60*view.TICK_SECONDS+clip.length+0.1)
  ck(not view.player.is_playing(),"native death stops at source endpoint")
  view.advance_event_time(60*view.TICK_SECONDS+clip.length+1.0)
  ck(view.current_clip==&"Asuna_Original_Vital_Death" and not view.player.is_playing(),"dead state never resumes idle or restarts death")
  view.setup({"id":91,"character_id":"asuna","team":0,"cell":Vector2.ZERO,"range":3.0,"attack_ticks":60,"presentation":p},{},8)
  ck(not view.is_dead and view.current_clip==StringName(p.clips.idle),"reused view resets death state and selects native idle")
  view.consume(event)
  ck(not view.is_dead and view.current_clip==StringName(p.clips.idle),"prior generation death cannot kill reused view")
  var next_event:Dictionary=event.duplicate();next_event.generation=8;next_event.event_id="next-round-death"
  view.consume(next_event)
  ck(view.is_dead and view.player.current_animation=="Asuna_Original_Vital_Death","new generation can play native death again")
  ck(view.diagnostics().warnings.is_empty(),"death lifecycle reuse produces no warnings")
 view.free()
func run()->void:
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 profile=profiles.asuna.duplicate(true)
 death_event_fixture(profile)
 if "--death-only" in OS.get_cmdline_user_args():
  print("ASUNA DEATH EVENT CHECKS=",checks," FAILURES=",failures)
  quit(1 if failures else 0);return
 # This fixture isolates animation tests from the separately tested anchor migration.
 profile["anchors"]=[]
 for field in Guard.FIELDS:ck(profile.has(field),"Asuna profile declares "+field)
 if not profile.has("animation_library_path"):quit(1);return
 patch("animation_library_path","res://assets/characters/asuna/does-not-exist.res","missing library")
 patch("animation_library_manifest_path","res://assets/characters/asuna/no-manifest.res","missing manifest")
 patch("animation_library_sha256","0".repeat(64),"wrong native library SHA")
 patch("animation_library_manifest_sha256","0".repeat(64),"wrong native manifest SHA")
 patch("source_glb_sha256","0".repeat(64),"wrong source SHA")
 patch("normalize_durations",true,"normalizing override")
 for field in Guard.FIELDS:
  var changed:Dictionary=profile.duplicate(true);changed.erase(field);fail_closed(changed,"missing field "+field)
 var manifest:Resource=load(profile.animation_library_manifest_path)
 var contract:Dictionary=manifest.get_meta("contract")
 fail_closed(saved_manifest(null,"empty"),"manifest without contract")
 for field in ["source_glb_sha256","model_path","library_sha256","structure_sha256","rest_sha256"]:
  var changed:Dictionary=contract.duplicate(true);changed[field]="wrong";fail_closed(saved_manifest(changed,field),"mismatched manifest "+field)
 var malformed:Dictionary=contract.duplicate(true);malformed.library_name=42;fail_closed(saved_manifest(malformed,"malformed-library-name"),"malformed library name")
 var changed:Dictionary=contract.duplicate(true);changed.clips.erase(changed.clips.keys()[0]);fail_closed(saved_manifest(changed,"clips"),"missing manifest clip")
 changed=contract.duplicate(true);changed.clips[changed.clips.keys()[0]].keys=0;fail_closed(saved_manifest(changed,"keys"),"mismatched manifest key count")
 var missing_clip:Dictionary=profile.duplicate(true);missing_clip.clips.ex="MissingDeclaredClip";fail_closed(missing_clip,"missing declared action clip")
 var source_missing:Dictionary=profile.duplicate(true);source_missing.erase("source_glb_sha256");fail_closed(source_missing,"missing source hash")
 # Wrong native Resource type is authenticated as bytes but never accepted as a library.
 var invalid_resource:Resource=Resource.new();var wrong_path:String="user://asuna-wrong-type.res"
 ck(ResourceSaver.save(invalid_resource,wrong_path)==OK,"wrong-type fixture saves")
 var wrong_type:Dictionary=profile.duplicate(true);wrong_type.animation_library_path=wrong_path;wrong_type.animation_library_sha256=FileAccess.get_sha256(wrong_path)
 fail_closed(wrong_type,"wrong native library resource type")
 var selected=view_for(profile)
 ck(selected.player!=null,"valid native library is selected through UnitView")
 if selected.player==null:quit(1);return
 ck(selected.diagnostics().warnings.is_empty(),"valid override has no warnings")
 var library:AnimationLibrary=selected.player.get_animation_library("")
 ck(library.get_meta("source_glb_sha256","")==profile.source_glb_sha256,"selected library retains provenance")
 var total:int=0
 for name in library.get_animation_list():
  var clip:Animation=library.get_animation(name)
  ck(clip.length==contract.clips[String(name)].length,"source duration preserved "+String(name))
  ck(clip.get_meta("source_extras",{})==contract.clips[String(name)].source_extras,"source metadata preserved "+String(name))
  ck(clip.loop_mode==(Animation.LOOP_LINEAR if String(name) in [profile.clips.idle,profile.clips.walk] else Animation.LOOP_NONE),"existing loop policy "+String(name))
  for i in clip.get_track_count():total+=clip.track_get_key_count(i)
 ck(total==262988,"all 262970 source keys plus 18 generated constants survive")
 ck(library.get_animation("Asuna_Original_Exs_Root__RootMotion").get_meta("source_identity").path_id=="-3736668486879208201","RootMotion source identity stays separate")
 ck(library.get_animation("Asuna_Original_Exs_Root__Animation").get_meta("source_identity").path_id=="4607550408865671297","Animation source identity stays separate")
 var raw_profile:Dictionary=profile.duplicate(true)
 for field in Guard.FIELDS:raw_profile.erase(field)
 var raw=view_for(raw_profile);var raw_library:AnimationLibrary=raw.player.get_animation_library("")
 ck(raw_library!=library,"raw imported and restored caches are isolated")
 ck(not raw_library.has_meta("source_glb_sha256"),"raw path receives no override metadata")
 var second=view_for(profile)
 ck(second.player!=selected.player and second.player.get_animation_library("")==library,"immutable clip cache shared with independent players")
 var sidecar:AnimationLibrary=load(profile.animation_library_path)
 ck(sidecar!=library,"immutable resource duplicated before applying loop policy")
 ck(Guard.digest(Guard.structure(sidecar))==contract.structure_sha256,"source resource structure unchanged after playback setup")
 selected.player.play(profile.clips.ex);selected.player.seek(0.507291675,true)
 ck(second.player.current_animation==profile.clips.idle,"one player seek never changes another actor")
 selected.player.play(profile.clips.walk);selected.player.advance(library.get_animation(profile.clips.walk).length*2.25)
 ck(selected.player.is_playing() and selected.player.current_animation==profile.clips.walk,"walk loops beyond its endpoint")
 selected.player.play(profile.clips.ex);selected.player.seek(0.25,true)
 ck(selected.player.current_animation==profile.clips.ex and absf(selected.player.current_animation_position-0.25)<1e-8,"clip switch preserves source time")
 selected.player.seek(library.get_animation(profile.clips.ex).length,true);selected.player.advance(0.1)
 ck(not selected.player.is_playing(),"nonlooping EX stops at source endpoint")
 for key in profiles:
  if key!="asuna":ck(not Guard.configured(profiles[key]),"existing profile stays on original branch: "+key)
 # Preload then replace the exact same path: digest-qualified selection must not
 # trust the engine's stale path-only resource cache or share a prior playback cache.
 var replacement:AnimationLibrary=sidecar.duplicate(true)
 var replacement_path:String="user://asuna-replaced-library.res"
 ck(ResourceSaver.save(replacement,replacement_path)==OK,"initial replacement fixture saves")
 var stale:AnimationLibrary=load(replacement_path)
 var mutable:Animation=replacement.get_animation(profile.clips.ex)
 var key:Variant=mutable.track_get_key_value(0,0);key.x+=0.125;mutable.track_set_key_value(0,0,key)
 ck(ResourceSaver.save(replacement,replacement_path)==OK,"same-path replacement fixture saves")
 var replacement_profile:Dictionary=profile.duplicate(true)
 replacement_profile.animation_library_path=replacement_path;replacement_profile.animation_library_sha256=FileAccess.get_sha256(replacement_path)
 var replacement_contract:Dictionary=contract.duplicate(true);replacement_contract.library_sha256=replacement_profile.animation_library_sha256
 var replacement_manifest:Resource=Resource.new();replacement_manifest.set_meta("contract",replacement_contract)
 var replacement_manifest_path:String="user://asuna-replaced-manifest.res"
 ck(ResourceSaver.save(replacement_manifest,replacement_manifest_path)==OK,"replacement manifest fixture saves")
 replacement_profile.animation_library_manifest_path=replacement_manifest_path;replacement_profile.animation_library_manifest_sha256=FileAccess.get_sha256(replacement_manifest_path)
 var replaced=view_for(replacement_profile)
 ck(replaced.player!=null,"new authenticated bytes selected despite stale engine path cache")
 if replaced.player!=null:
  var replacement_selected:AnimationLibrary=replaced.player.get_animation_library("")
  ck(replacement_selected!=library,"sidecar identity/content hash isolates playback cache")
  ck(replacement_selected.get_animation(profile.clips.ex).track_get_key_value(0,0)==key,"new digest loads actual current sidecar bytes")
  ck(stale.get_animation(profile.clips.ex).track_get_key_value(0,0)!=key,"fixture retained genuinely stale cached resource")
 replaced.free();second.free();raw.free();selected.free()
 # Validate importer-target mutation separately from hashed resource mismatches.
 var model:Node3D=load(profile.model_path).instantiate();root.add_child(model)
 var player:AnimationPlayer=model.find_child("AnimationPlayer",true,false)
 var original:AnimationLibrary=player.get_animation_library("")
 var copied:AnimationLibrary=original.duplicate(true)
 var first:Animation=copied.get_animation(copied.get_animation_list()[0]);first.track_set_path(0,NodePath("MissingAnimationTarget"))
 ck(not Guard.target_error(player,copied).is_empty(),"unresolved target is rejected")
 var before:String=Guard.rest_signature(model)
 var skeleton:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
 var rest:Transform3D=skeleton.get_bone_rest(0);rest.origin.x+=0.01;skeleton.set_bone_rest(0,rest)
 ck(Guard.rest_signature(model)!=before,"local rest mutation changes signature")
 ck(not Guard.select(profile,model,player).error.is_empty(),"changed imported rest cannot select native sidecar")
 model.free()
 print("ASUNA ANIMATION LIBRARY CHECKS=",checks," FAILURES=",failures)
 quit(1 if failures else 0)
