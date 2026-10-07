extends SceneTree
var failures:Array=[]
var report:Dictionary={"raw_files":0,"raw_meshes":0,"vfx_pixels":0,"texture_metadata":0,"models":0,"character_textures":0,"portraits":0,"skill_icons":0,"audio_bus_layouts":0,"audio_peak_limiters":0,"audio_streams":0,"ordinary_audio_streams":0,"ordinary_audio_bindings":0,"ordinary_audio_scheduled":0,"ordinary_audio_issues":[],"ordinary_audio_choices":[],"shaders":0,"clips":0,"vfx_issues":[],"limitations":[]}
class AssetView extends Node3D:
 var _model:Node3D
 func muzzle_transform()->Transform3D:return _model.global_transform
 func hit_position()->Vector3:return global_position+Vector3.UP*0.7
func ck(ok:bool,message:String)->void:
 if not ok:failures.append(message);printerr("FAIL ",message)
# The source gate hashes the GLB before import. A PCK may contain only its remap;
# runtime provenance therefore comes from exact native resource bytes + metadata.
func animation_sample(clip:Animation,track:int,time:float)->Array:
 match clip.track_get_type(track):
  Animation.TYPE_POSITION_3D:
   var value:Vector3=clip.position_track_interpolate(track,time)
   return [value.x,value.y,value.z]
  Animation.TYPE_ROTATION_3D:
   var value:Quaternion=clip.rotation_track_interpolate(track,time)
   return [value.x,value.y,value.z,value.w]
  Animation.TYPE_SCALE_3D:
   var value:Vector3=clip.scale_track_interpolate(track,time)
   return [value.x,value.y,value.z]
 return []
func animation_sample_matches(actual:Array,expected:Array,rotation:bool)->bool:
 if actual.size()!=expected.size() or actual.size() not in [3,4]:return false
 for value in actual+expected:
  if (not value is float and not value is int) or not is_finite(float(value)):return false
 if rotation:
  if actual.size()!=4:return false
  # Use scalar doubles, avoiding float32 Vector4 dot rounding at small angles.
  var dot:=0.0;var norm_a:=0.0;var norm_b:=0.0
  for i in 4:
   dot+=float(actual[i])*float(expected[i]);norm_a+=float(actual[i])*float(actual[i]);norm_b+=float(expected[i])*float(expected[i])
  if norm_a<=0.0 or norm_b<=0.0:return false
  return 2.0*acos(clampf(absf(dot)/sqrt(norm_a*norm_b),0.0,1.0))<=0.00001
 for i in actual.size():
  if absf(float(actual[i])-float(expected[i]))>0.000001:return false
 return true
func verify_animation_clip(clip:Animation,expected:Dictionary,label:String)->Dictionary:
 var tracks:int=clip.get_track_count();var keys:=0;var samples_checked:=0
 for track in tracks:keys+=clip.track_get_key_count(track)
 ck(tracks==int(expected.get("tracks",-1)) and tracks>0,"override track count "+label)
 ck(keys==int(expected.get("keys",-1)) and keys>0,"override original key count "+label)
 ck(absf(clip.length-float(expected.get("length",-1)))<=0.000001,"override authored length "+label)
 for field in ["source_identity","source_extras"]:
  ck(expected.has(field) and clip.has_meta(field) and clip.get_meta(field)==expected.get(field),"override clip metadata "+field+" "+label)
 var samples=expected.get("samples",[])
 ck(samples is Array and not samples.is_empty(),"override sentinel samples exist "+label)
 var playback_loop:=clip.loop_mode
 if samples is Array:
  for sample in samples:
   var valid:bool=sample is Array and sample.size()==4
   if valid:valid=(sample[0] is int and sample[1] is int and (sample[2] is int or sample[2] is float) and sample[3] is Array)
   if valid:valid=(int(sample[0])>=0 and int(sample[0])<tracks and float(sample[2])>=0.0 and float(sample[2])<=clip.length+0.000001)
   ck(valid,"valid override sentinel "+label)
   if not valid:continue
   var track:int=int(sample[0]);var type:int=clip.track_get_type(track)
   ck(type==int(sample[1]),"override sentinel track type "+label)
   var actual:Array=animation_sample(clip,track,float(sample[2]))
   ck(animation_sample_matches(actual,sample[3],type==Animation.TYPE_ROTATION_3D),"override source sentinel value "+label+":"+str(track)+"@"+str(sample[2]))
   # Also prove the stored terminal key, without replacing actual playback sampling.
   var last_key:int=clip.track_get_key_count(track)-1
   if last_key>=0 and float(sample[2])==clip.track_get_key_time(track,last_key):
    var terminal=clip.track_get_key_value(track,last_key);var components:Array=[]
    if terminal is Vector3:components=[terminal.x,terminal.y,terminal.z]
    elif terminal is Quaternion:components=[terminal.x,terminal.y,terminal.z,terminal.w]
    ck(animation_sample_matches(components,sample[3],type==Animation.TYPE_ROTATION_3D),"override stored terminal key "+label+":"+str(track))
   samples_checked+=1
 ck(clip.loop_mode==playback_loop,"selected animation loop policy remains immutable "+label)
 report.animation_override_clips+=1;report.animation_override_keys+=keys;report.animation_override_samples+=samples_checked
 return {"length":clip.length,"tracks":tracks,"keys":keys,"samples":samples_checked,
  "source_identity":clip.get_meta("source_identity",{}),"source_extras":clip.get_meta("source_extras",{})}
func verify_animation_overrides(manifest:Dictionary,profiles:Dictionary)->void:
 report.animation_override_profiles=[];report.animation_override_models=0;report.animation_override_libraries=0
 report.animation_override_clips=0;report.animation_override_keys=0;report.animation_override_samples=0
 report.animation_override_issues=[];report.animation_override_details={}
 var declared:Array=[]
 for character in profiles:
  if profiles[character].has("animation_library_path"):declared.append(str(character))
 declared.sort()
 var expected_profiles:Array=[]
 for row in manifest.get("animation_overrides",[]):expected_profiles.append(str(row.character))
 expected_profiles.sort()
 ck(declared==expected_profiles,"all configured optional animation profiles are in dependency manifest")
 if declared.is_empty():return
 var UnitView=load("res://scripts/unit_view.gd")
 ck(UnitView is GDScript,"real UnitView script for animation overrides")
 if not UnitView is GDScript:return
 for row in manifest.get("animation_overrides",[]):
  var character:String=str(row.character)
  if not profiles.has(character):ck(false,"override profile exists "+character);continue
  var profile:Dictionary=profiles[character]
  for field in ["model_path","source_glb_sha256","animation_library_path","animation_library_manifest_path","animation_library_sha256","animation_library_manifest_sha256"]:
   ck(profile.get(field)==row.get(field),"override profile matches pinned manifest "+character+":"+field)
  var resource=load(str(row.animation_library_manifest_path))
  var library=load(str(row.animation_library_path))
  ck(resource is Resource and library is AnimationLibrary,"native animation resources load "+character)
  if not resource is Resource or not library is AnimationLibrary:continue
  var contract=resource.get_meta("contract",{})
  ck(contract is Dictionary and int(contract.get("schema_version",-1))==1,"native animation contract schema "+character)
  if not contract is Dictionary or contract.is_empty():continue
  ck(contract.get("model_path")==row.model_path and contract.get("source_glb_sha256")==row.source_glb_sha256,"native animation contract source "+character)
  ck(contract.get("library_sha256")==row.animation_library_sha256,"native animation contract library digest "+character)
  var clips=contract.get("clips",{})
  ck(clips is Dictionary and not clips.is_empty(),"native animation contract clips "+character)
  if not clips is Dictionary or clips.is_empty():continue
  var view=UnitView.new();root.add_child(view)
  view.setup({"id":-101,"character_id":character,"team":0,"range":1.0,"cell":Vector2.ZERO,"presentation":profile},profile.get("durations",{}),7701)
  var diagnostics:Dictionary=view.diagnostics()
  var issues=diagnostics.get("warnings",["missing warnings diagnostics"])
  ck(issues is Array and issues.is_empty(),"real UnitView override warnings empty "+character)
  if issues is Array:
   for issue in issues:report.animation_override_issues.append({"character":character,"warning":issue})
  ck(is_instance_valid(view.player),"real UnitView override player "+character)
  if not is_instance_valid(view.player):view.free();continue
  var selected:AnimationLibrary
  for library_name in view.player.get_animation_library_list():
   var candidate:AnimationLibrary=view.player.get_animation_library(library_name)
   if candidate.get_meta("source_glb_sha256","")==row.source_glb_sha256:
    ck(selected==null,"only one selected override library "+character);selected=candidate
  ck(selected!=null,"real UnitView selected native override "+character)
  if selected==null:view.free();continue
  for field in ["source_glb_sha256","structure_sha256","rest_sha256"]:
   ck(contract.has(field) and selected.has_meta(field) and selected.get_meta(field)==contract.get(field) and library.get_meta(field,"")==contract.get(field),"selected override library metadata "+character+":"+field)
  var clip_names:Array=[]
  for clip_name in selected.get_animation_list():clip_names.append(str(clip_name))
  clip_names.sort();var expected_names:Array=clips.keys();expected_names.sort()
  ck(clip_names==expected_names,"selected override exact clip inventory "+character)
  for required in row.required_clips:ck(selected.has_animation(str(required)),"selected override required clip "+character+":"+str(required))
  var details:Dictionary={"model_path":row.model_path,"source_glb_sha256":row.source_glb_sha256,
   "library_sha256":row.animation_library_sha256,"manifest_sha256":row.animation_library_manifest_sha256,
   "structure_sha256":selected.get_meta("structure_sha256",""),"rest_sha256":selected.get_meta("rest_sha256",""),"clips":{}}
  var total_tracks:=0;var total_keys:=0
  for clip_name in expected_names:
   if not selected.has_animation(str(clip_name)):continue
   var clip:Animation=selected.get_animation(str(clip_name))
   var expected=clips[clip_name]
   ck(expected is Dictionary,"valid clip contract "+character+":"+str(clip_name))
   if not expected is Dictionary:continue
   var item:Dictionary=verify_animation_clip(clip,expected,character+":"+str(clip_name))
   details.clips[clip_name]=item;total_tracks+=int(item.tracks);total_keys+=int(item.keys)
  ck(total_tracks==int(contract.get("tracks",-1)) and total_keys==int(contract.get("keys",-1)),"selected override aggregate counts "+character)
  report.animation_override_profiles.append(character);report.animation_override_models+=1;report.animation_override_libraries+=1
  report.animation_override_details[character]=details
  view.free()
 report.animation_override_profiles.sort()

func _initialize()->void:call_deferred("run")
func run()->void:
 var args:PackedStringArray=OS.get_cmdline_user_args()
 if args.size()!=2:printerr("Expected manifest and output paths");quit(2);return
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
 var Source=load("res://vfx/native_source.gd")
 var Materials=load("res://vfx/materials/native_materials.gd")
 ck(Source!=null and Materials!=null,"native runtime scripts load")
 if Source==null or Materials==null:quit(1);return
 for row in manifest.files:
  var path:String="res://"+str(row.path);var category:String=str(row.category)
  if category in ["runtime_json","vfx_texture_json","vfx_texture_png","mesh_raw","animation_libraries","animation_library_manifests"]:
   ck(FileAccess.file_exists(path),"raw file exists "+path)
   ck(FileAccess.get_sha256(path)==str(row.sha256),"raw SHA256 "+path);report.raw_files+=1
  if category=="mesh_raw":
   var mesh=Source.obj_mesh(path)
   ck(mesh is ArrayMesh and mesh.get_surface_count()>0,"raw native mesh loads "+path)
   if mesh is ArrayMesh and mesh.get_surface_count()>0:ck(mesh.surface_get_array_len(0)>0 and mesh.surface_get_array_index_len(0)>0,"raw mesh has geometry "+path)
   report.raw_meshes+=1
  elif category in ["runtime_json","vfx_texture_json"]:
   var parsed=Source.read_json(path)
   ck(parsed is Dictionary and not parsed.is_empty(),"runtime JSON dictionary "+path)
   if category=="vfx_texture_json":report.texture_metadata+=1
  elif category=="vfx_texture_png":
   var texture=Materials._load_texture({"png":path},"")
   ck(texture is Texture2D,"native VFX texture loads "+path)
   var source:=Image.new();ck(source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK,"raw PNG decodes "+path);source.flip_y();source.convert(Image.FORMAT_RGBA8)
   if texture is Texture2D:
    var actual:Image=texture.get_image();actual.convert(Image.FORMAT_RGBA8)
    ck(actual.get_size()==source.get_size() and actual.get_data()==source.get_data(),"exact flipped VFX pixels "+path)
   report.vfx_pixels+=1
  elif category in ["character_textures","portraits","skill_icons"]:
   var texture=load(path);ck(texture is Texture2D,"imported texture loads "+path)
   report[category]+=1
  elif category=="audio_streams":
   var stream=load(path);ck(stream is AudioStreamWAV and stream.get_length()>0,"imported audio loads "+path);report.audio_streams+=1
  elif category=="ordinary_audio_streams":
   var stream=load(path);ck(stream is AudioStreamWAV and stream.get_length()>0,"ordinary imported audio loads "+path)
   if stream is AudioStreamWAV:
    ck(stream.format==AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate==int(row.sample_rate_hz) and stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,"ordinary PCM import format "+path)
    var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(stream.data)
    ck(stream.data.size()==int(row.frames)*2 and digest.finish().hex_encode()==str(row.pcm_sha256),"ordinary imported PCM SHA256 and length "+path)
   report.ordinary_audio_streams+=1
  elif category=="audio_bus_layout":
   ck(load(path) is AudioBusLayout,"combat bus layout resource loads")
   ck(ProjectSettings.get_setting("audio/buses/default_bus_layout","")==path,"project references the packaged combat bus layout")
   report.audio_bus_layouts+=1
   var master:int=AudioServer.get_bus_index("Master")
   ck(master==0 and AudioServer.bus_count==1 and AudioServer.get_bus_effect_count(master)==1,"single Master peak protection is active on startup")
   if master==0 and AudioServer.get_bus_effect_count(master)==1:
    var limiter=AudioServer.get_bus_effect(master,0)
    ck(limiter is AudioEffectHardLimiter,"startup effect is modern hard limiter")
    if limiter is AudioEffectHardLimiter:
     ck(AudioServer.is_bus_effect_enabled(master,0) and not AudioServer.is_bus_bypassing_effects(master),"peak protection enabled")
     ck(is_equal_approx(limiter.pre_gain_db,0.0) and is_equal_approx(limiter.ceiling_db,-0.3) and is_equal_approx(limiter.release,0.1),"explicit peak protection parameters preserved")
     report.audio_peak_limiters+=1
  elif category=="audio_runtime_scripts":
   ck(load(path) is GDScript,"audio runtime script loads "+path)
  elif category=="prop_fallback_or_shader":
   var item=load(path)
   if path.ends_with(".gdshader"):ck(item is Shader,"shader resource "+path);report.shaders+=1
   elif path.ends_with(".glb") or path.ends_with(".fbx"):
    ck(item is PackedScene,"prop/fallback model resource "+path)
    if item is PackedScene:
     var instance=item.instantiate();ck(instance!=null,"prop/fallback model instantiation "+path);instance.free()
   else:ck(item is Texture2D,"prop/fallback texture "+path)
 var icon_resolver=load("res://scripts/native_skill_icons.gd").new()
 for character in manifest.summary.active_roster:
  for slot in ["ex","basic","sub"]:
   var icon_key:String=icon_resolver.skill_key(character,slot)
   ck(not icon_key.is_empty() and icon_resolver.texture(icon_key) is Texture2D and icon_resolver.region(icon_key).has_area(),"packaged skill icon "+character+"/"+slot)
 print("RAW_RESOURCE_CHECKPOINT ",JSON.stringify(report))
 var profiles:Dictionary=Source.read_json("res://data/character-presentations.json")
 verify_animation_overrides(manifest,profiles)
 var compact:Dictionary=Source.read_json("res://data/effects/battle-events-compact.json")
 var views:Dictionary={};var units:Array=[];var ids:Dictionary={};var idx:int=1
 for character in compact.activeRoster:
  var packed=load(profiles[character].model_path);ck(packed is PackedScene,"character PackedScene "+character)
  if not packed is PackedScene:continue
  var view:=AssetView.new();root.add_child(view);view._model=packed.instantiate();view.add_child(view._model)
  view._model.scale*=float(profiles[character].model_scale);view._model.rotation.y=float(profiles[character].model_yaw)
  var animations:Array=view._model.find_children("*","AnimationPlayer",true,false);ck(not animations.is_empty(),"character AnimationPlayer "+character)
  if not animations.is_empty():
   var player:AnimationPlayer=animations[0]
   for clip in profiles[character].clips.values():
    if str(clip).is_empty():continue
    ck(player.has_animation(str(clip)),"declared clip "+character+":"+str(clip));report.clips+=1
  views[idx]=view;ids[character]=idx;units.append({"id":idx,"character_id":character});idx+=1;report.models+=1
 var OrdinaryAudio=load("res://scripts/ordinary_combat_audio.gd")
 ck(OrdinaryAudio!=null,"ordinary audio scheduler loads")
 if OrdinaryAudio!=null:
  var ordinary=OrdinaryAudio.new();root.add_child(ordinary);ordinary.output_enabled=false;ordinary.begin_battle(units,44,1003)
  var ordinary_manifest:Dictionary=Source.read_json("res://data/audio/native-ordinary-sfx.json")
  for binding in ordinary_manifest.bindings:
   ordinary.consume_state({"type":"enter","actor_id":ids[binding.character],"character_id":binding.character,"generation":44,
    "token":binding.binding_id,"action_id":binding.binding_id,"state_name":binding.state_name,"native_clip":binding.native_clip,
    "start_time":1.0,"source_offset":0.0,"speed":1.0,"planned_end_time":10.0})
  var ordinary_diagnostics:Dictionary=ordinary.diagnostics()
  report.ordinary_audio_bindings=int(ordinary_diagnostics.manifest_events)
  report.ordinary_audio_scheduled=int(ordinary_diagnostics.scheduled_count)
  report.ordinary_audio_issues=ordinary_diagnostics.issues
  report.ordinary_audio_choices=ordinary_diagnostics.choices
  ck(report.ordinary_audio_bindings==28 and report.ordinary_audio_scheduled==28,"all 14 attack and 14 reload audio bindings load and schedule")
  ck(report.ordinary_audio_issues.is_empty() and int(ordinary_diagnostics.invalid_state_records)==0,"ordinary audio resource/state diagnostics clean")
  ordinary.reset(45);ordinary.free()
 var Glue=load("res://scripts/native_combat_vfx.gd");var glue=Glue.new();root.add_child(glue);glue.configure(profiles);glue.begin_roster(views,units,44)
 for character in compact.activeRoster:
  for timeline in compact.characters[character].timelines:
   if timeline.kind not in ["ex","basic"]:continue
   for event in timeline.events:
    if event.kind!="effect":continue
    for binding in event.bindings:
     var hierarchy:String=str(binding.get("hierarchy",""))
     if hierarchy.is_empty():continue
     ck(glue.resolve_live_anchor(ids[character],hierarchy)!=null,"GLB effect anchor "+character+":"+hierarchy)
 glue.update_time(0)
 for ability in ["ex","basic"]:
  for character in compact.activeRoster:glue.consume({"type":"skill" if ability=="ex" else "basic","ability":ability,"actor_id":ids[character],"tick":0,"generation":44,"event_id":ability+"-"+character},units)
 glue.update_time(0.5)
 report.vfx_issues=glue.diagnostics().issues
 report.vfx_native_issues=glue.diagnostics().native.get("issues",[])
 report.vfx_timelines_spawned=glue.diagnostics().timelines_spawned
 ck(report.vfx_timelines_spawned==28,"all 14 EX and 14 basic timelines spawned")
 report.dependency_diagnostics=[]
 for issue in report.vfx_issues+report.vfx_native_issues:
  if issue.code in ["mesh_load_failed","missing_textures","missing_material","missing_prefab","missing_timeline","missing_effect_asset"]:report.dependency_diagnostics.append(issue)
 glue.reset(45);glue.free()
 for view in views.values():view.free()
 var Session=load("res://core/game_session.gd");var Save=load("res://core/session_save_store.gd");var Settings=load("res://core/user_settings.gd")
 var session=Session.new();ck(session.new_game(1003).ok,"packaged session starts")
 ck(session._battle_options(1003,"p0","p1").get("area_ex_coverage_targeting",false)==true and session._battle_options(1003,"p2","p3").get("area_ex_coverage_targeting",false)==true,"packaged player and NPC area EX policy enabled")
 ck(session.command({"type":"set_shop_locked","locked":true}).ok and session.rules.get_player().shop_locked,"packaged one-round retention works")
 ck(session.command({"type":"set_normal_target_policy","policy":"wounded"}).ok,"packaged normal target tactic works")
 ck(session.rules.snapshot().config.reinforcement_recruitment==1 and session.rules.get_reinforcement().is_empty(),"packaged new match enables scheduled reinforcements without early offer")
 var save:Dictionary=session.export_save();ck(save.ok and save.data.version==Session.SAVE_VERSION and save.data.rules.version==6,"packaged canonical preparation saves")
 if save.ok:
  ck(Save.write_save(save.data,"user://export-check-session.json").ok,"packaged save store writes")
  var loaded:Dictionary=Save.read_save("user://export-check-session.json");ck(loaded.ok,"packaged save store reads")
  if loaded.ok:ck(session.restore_save(loaded.data).ok and session.rules.get_player().shop_locked and session.normal_target_policy()=="wounded","packaged session restores retained shop and tactic")
 var settings_values:Dictionary={"volume":0.25,"muted":true,"fullscreen":false,"reduce_smoke":true}
 ck(Settings.write_settings(settings_values,"user://export-check-settings.cfg").ok,"packaged settings writes")
 var setting_result:Dictionary=Settings.read_settings("user://export-check-settings.cfg");ck(setting_result.ok and setting_result.values==Settings.validate(settings_values).values,"packaged settings reload")
 var RecruitmentHints=load("res://core/recruitment_hints.gd")
 ck(RecruitmentHints!=null,"packaged recruitment helper loads")
 report.recruitment_helper_loaded=RecruitmentHints!=null
 for module in ['protocol','room_rules','authority','duel_runtime','view_codec','session_view']:
  ck(load('res://core/lan/'+module+'.gd') is GDScript,'packaged LAN core '+module)
 for module in ['transport','room_controller','lobby','game_client']:
  ck(load('res://scripts/lan/'+module+'.gd') is GDScript,'packaged LAN client '+module)
 var lan_authority=load('res://core/lan/authority.gd').new()
 ck(lan_authority.start_match(31).ok,'packaged LAN match starts')
 var lan_codec=load('res://core/lan/view_codec.gd')
 var lan_view=load('res://core/lan/session_view.gd').new()
 ck(lan_view.accept(lan_codec.unpack(JSON.parse_string(JSON.stringify(lan_codec.pack(lan_authority.view_for('p1'))))),'p1').ok,'packaged LAN codec private view roundtrip')
 lan_authority.close()
 var game=load("res://game.tscn");ck(game is PackedScene,"packaged main scene loads")
 if game is PackedScene:
  var app=game.instantiate();app.save_path="user://export-check-app-"+str(Time.get_ticks_usec())+".json";app.settings_path="user://export-check-app.cfg";root.add_child(app);app.set_process(false);await process_frame
  ck(app.flow_state=="title" and app.game==null and app.title_menu!=null,"packaged main scene boots to title without gameplay")
  app.request_new_game()
  for frame in range(300):
   if app.flow_state!="loading":break
   await process_frame
  ck(app.flow_state=="game" and is_instance_valid(app.game),"packaged explicit new game loads gameplay scene")
  if is_instance_valid(app.game):
   var runtime=app.game;runtime.set_process(false)
   ck(runtime.session!=null and runtime.game_menu!=null and runtime.shop_lock_button!=null and runtime.normal_target_selector!=null and runtime.game_menu.reduce_smoke!=null and runtime.reinforcement_panel!=null and runtime.reinforcement_button!=null and runtime.recruitment_preview!=null and runtime.shop_preview_buttons.size()==5,"packaged gameplay has menu, retention, tactic, smoke and recruitment UI")
   ck(runtime.round_result_panel!=null and runtime.game_menu.title_button.visible,"packaged gameplay has result presenter and title navigation")
   ck(runtime.session.rules_profile()==3 and runtime.session._battle_options(1003,"p0","p1").max_ticks==1800 and runtime.session._battle_options(1003,"p0","p1").timeout_total_hp,"packaged new game uses versioned 90-second HP rules")
   ck(runtime.ordinary_audio!=null and runtime.stage.ordinary_audio_state.is_connected(runtime._consume_ordinary_state),"packaged gameplay owns connected ordinary audio scheduler")
   var preview_before:Dictionary=runtime.session.export_save()
   runtime._preview_shop_offer(0)
   ck(runtime.recruitment_preview.visible and runtime.recruitment_preview.skill_labels.size()==3 and runtime.session.export_save()==preview_before,"packaged recruitment preview is populated and read-only")
   runtime.recruitment_preview.close_panel();runtime.request_return_to_title()
   await process_frame;await process_frame
   ck(app.flow_state=="title" and app.game==null and not app.title_menu.continue_button.disabled,"packaged return tears down gameplay and refreshes checkpoint")
   app.request_continue()
   for frame in range(300):
    if app.flow_state!="loading":break
    await process_frame
   ck(app.flow_state=="game" and is_instance_valid(app.game) and app.game.session.phase()=="preparation","packaged continue restores preparation")
  app.queue_free();await process_frame
 report.failures=failures;report.failure_count=failures.size();report.passed=failures.is_empty();report.features={"editor":OS.has_feature("editor"),"debug":OS.is_debug_build(),"display":DisplayServer.get_name()}
 var output:=FileAccess.open(args[1],FileAccess.WRITE);output.store_string(JSON.stringify(report,"  "));output.close();print("PACKAGED_RUNTIME_RESULT passed=",report.passed," failures=",report.failure_count," raw_meshes=",report.raw_meshes," vfx_pixels=",report.vfx_pixels," models=",report.models," timelines=",report.vfx_timelines_spawned," dependency_diagnostics=",JSON.stringify(report.dependency_diagnostics));quit(0 if failures.is_empty() else 1)
