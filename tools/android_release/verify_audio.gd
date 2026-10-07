extends SceneTree
## Resource-only acceptance against bytes extracted from the APK, never gameplay.
var failures:Array=[]
var report:Dictionary={"ordinary_audio_streams":0,"skill_audio_streams":0}
func check(ok:bool,message:String)->void:
 if not ok:failures.append(message);printerr("FAIL ",message)
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:PackedStringArray=OS.get_cmdline_user_args()
 if args.size()!=3:printerr("Expected APK audio ZIP, manifest, report");quit(2);return
 check(ProjectSettings.load_resource_pack(args[0]),"mount APK-only audio resources")
 var manifest=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
 if not manifest is Dictionary:printerr("Invalid dependency manifest");quit(2);return
 for row in manifest.files:
  var category:String=str(row.category)
  if category not in ["ordinary_audio_streams","audio_streams"]:continue
  var path:String="res://"+str(row.path)
  var stream=load(path)
  check(stream is AudioStreamWAV and stream.get_length()>0,"packaged WAV loads "+path)
  if category=="audio_streams":report.skill_audio_streams+=1;continue
  report.ordinary_audio_streams+=1
  if not stream is AudioStreamWAV:continue
  check(stream.format==AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate==int(row.sample_rate_hz) and stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,"ordinary PCM format/rate/loop "+path)
  var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(stream.data)
  check(stream.data.size()==int(row.frames)*2 and digest.finish().hex_encode()==str(row.pcm_sha256),"ordinary PCM SHA256 and length "+path)
 report["failures"]=failures;report["passed"]=failures.is_empty()
 var output=FileAccess.open(args[2],FileAccess.WRITE)
 if output==null:printerr("Cannot create audio report");quit(2);return
 output.store_string(JSON.stringify(report,"  ")+"\n");output.close()
 print(JSON.stringify(report))
 quit(0 if failures.is_empty() else 1)
