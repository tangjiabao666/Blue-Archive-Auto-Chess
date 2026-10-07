extends SceneTree
var failures:=0
var checks:=0
func _initialize()->void:call_deferred("run")
func run()->void:
 var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/native-skill-sfx.json"))
 var audio=load("res://scripts/native_combat_audio.gd")
 for scenario in ["unverified_time_scale","unverified_delay","loop","negative_pitch","ambiguous_pool","muted","enhanced_basic"]:
  var data:Dictionary=source.duplicate(true)
  for row in data.records:
   match scenario:
    "unverified_time_scale":row.timeScale=2.0
    "unverified_delay":row.delaySeconds=0.5;row.nativeAudioData.Delay=0.5
    "loop":row.loop=true;row.nativeAudioData.Loop=1
    "negative_pitch":row.pitch=-1.0;row.nativeAudioData.Pitch=-1.0
    "ambiguous_pool":row.nativeAudioData.AudioClips.append(row.nativeAudioData.AudioClips[0].duplicate())
    "muted":row.muted=true
    "enhanced_basic":row.timelineKind="basic_enhanced"
  # An in-memory mounted test pack changes input without editing shipped sources.
  var fixture:String="user://audio-manifest-"+scenario+".json"
  var file:=FileAccess.open(fixture,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
  var pack_path:String="user://audio-manifest-"+scenario+".pck"
  var pack:=PCKPacker.new()
  if pack.pck_start(pack_path)!=OK or pack.add_file("res://data/audio/native-skill-sfx.json",fixture)!=OK or pack.flush()!=OK:quit(1);return
  if not ProjectSettings.load_resource_pack(pack_path,true):quit(1);return
  var node=audio.new();node.output_enabled=false;root.add_child(node)
  node.begin_roster([{"id":1,"character_id":"shiroko"}],8)
  node.consume({"type":"skill","ability":"ex","actor_id":1,"tick":0,"generation":8});node.update_time(1,false)
  checks+=1
  if node.diagnostics().manifest_events!=0 or node.diagnostics().scheduled_count!=0:
   failures+=1;push_error("must fail closed: "+scenario)
  node.free()
 print("COMBAT_AUDIO_MANIFEST_TESTS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
