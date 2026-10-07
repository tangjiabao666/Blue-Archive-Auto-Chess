extends "res://tools/windows_release/verify_runtime.gd"
## Focused source-side execution of the exact package override validator.
## This does not export or claim an actual empty-directory PCK pass.
func run()->void:
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 var profile:Dictionary=profiles.asuna
 var override:Dictionary={"character":"asuna","required_clips":[]}
 for field in ["model_path","source_glb_sha256","animation_library_path","animation_library_manifest_path","animation_library_sha256","animation_library_manifest_sha256"]:override[field]=profile[field]
 for name in profile.clips.values():
  if not String(name).is_empty() and not override.required_clips.has(name):override.required_clips.append(name)
 for pair in [[profile.model_path,profile.source_glb_sha256],[profile.animation_library_path,profile.animation_library_sha256],[profile.animation_library_manifest_path,profile.animation_library_manifest_sha256]]:
  ck(FileAccess.get_sha256(pair[0])==pair[1],"actual source/native resource bytes "+pair[0])
 verify_animation_overrides({"animation_overrides":[override]},profiles)
 ck(report.animation_override_models==1 and report.animation_override_libraries==1,"one inactive Asuna override verified")
 ck(report.animation_override_clips==12 and report.animation_override_keys==262988 and report.animation_override_samples==5472,"all optional source clips keys and sentinels covered")
 var args:PackedStringArray=OS.get_cmdline_user_args()
 if args.size()==1:
  var output:Dictionary=report.duplicate(true);output.failures=failures;output.passed=failures.is_empty()
  FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
 print("FOCUSED OPTIONAL ANIMATION PACKAGE CHECKS ",report.animation_override_clips," clips / ",report.animation_override_keys," keys / ",report.animation_override_samples," samples / FAILURES=",failures.size())
 quit(1 if not failures.is_empty() else 0)
