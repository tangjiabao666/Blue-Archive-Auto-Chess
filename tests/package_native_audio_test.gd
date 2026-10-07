extends SceneTree
## Builds a standalone test PCK with imported samples only (no raw WAV source).
## Run using --main-pack evidence/audio/native-audio-test.pck --script
## res://tests/test_native_combat_audio.gd from an empty directory.
func _initialize()->void:
 var pack:=PCKPacker.new()
 var path:="res://evidence/audio/native-audio-test.pck"
 if pack.pck_start(path)!=OK:quit(1);return
 var files:Array[String]=["res://project.godot","res://scripts/native_combat_audio.gd","res://tests/test_native_combat_audio.gd","res://data/audio/native-skill-sfx.json"]
 var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/native-skill-sfx.json"))
 for row in manifest.records:
  var source:String=row.resourcePath
  var config:=ConfigFile.new()
  if config.load(source+".import")!=OK:quit(1);return
  files.append(source+".import")
  files.append(str(config.get_value("remap","path")))
 for file in files:
  if pack.add_file(file,file)!=OK:quit(1);return
 if pack.flush()!=OK:quit(1);return
 print("AUDIO_TEST_PACK_BUILT ",files.size()," imported-resource files; zero raw WAVs");quit(0)
