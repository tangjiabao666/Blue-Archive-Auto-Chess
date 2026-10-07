extends SceneTree
## Lossless source-cache regression: all 13 active source trees, byte-exact assets.
const Source=preload("res://vfx/native_source.gd")
const Helpers=preload("res://tests/native_source_memory_helpers.gd")
const ROSTER=["shiroko","hoshino","hina","aru","yuuka","aris","serika","iori","tsubaki","nonomi","mutsuki","haruna","koharu"]
var failures:=0
func ck(ok:bool,label:String)->void:
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func run()->void:
 Source.clear_caches()
 var baseline:int=OS.get_static_memory_usage()
 for character in ROSTER:
  var path:String="res://data/effects/"+character+"/visual-templates.json"
  var before_hash:String=FileAccess.get_sha256(path)
  var data:Dictionary=Source.read_json(path)
  var original:Dictionary=Helpers.read_original(path)
  ck(data==original,"entire source JSON semantic equality: "+character)
  ck(var_to_bytes(data)==var_to_bytes(original),"source container order/scalars encode identically: "+character)
  ck(Helpers.deeply_read_only(data),"shared native source is recursively immutable: "+character)
  ck(is_same(data,Source.read_json(path)),"cache reuses source tree: "+character)
  ck(FileAccess.get_sha256(path)==before_hash,"source bytes unchanged: "+character)
  # Callers needing modified parameters already duplicate before changing them.
  var mutable:Dictionary=data.prefabs[0].nodes[0].duplicate(true)
  mutable.name="test-only mutation"
  ck(data.prefabs[0].nodes[0].name!="test-only mutation","explicit deep copy stays independently mutable: "+character)
  original={};data={};mutable={}
 var retained:int=OS.get_static_memory_usage()-baseline
 ck(retained<128*1024*1024,"all 13 exact template trees retain <128 MiB, actual="+str(retained))
 # The same source subtree may be shared only after exact encoding matches.
 var synthetic_path:String="user://native-memory-fixture/visual-templates.json"
 DirAccess.make_dir_recursive_absolute("user://native-memory-fixture")
 var synthetic_file:=FileAccess.open(synthetic_path,FileAccess.WRITE)
 synthetic_file.store_string('{"rows":[{"a":1,"b":2},{"a":1,"b":2},{"b":2,"a":1},{"a":1.0000000000000002,"b":2}]}');synthetic_file.close()
 var synthetic:Dictionary=Source.read_json(synthetic_path)
 var original_synthetic:Dictionary=Helpers.read_original(synthetic_path)
 ck(is_same(synthetic.rows[0],synthetic.rows[1]),"exact repeated dictionaries share one immutable subtree")
 ck(var_to_bytes(synthetic)==var_to_bytes(original_synthetic),"near-equal floats and differing key order remain exact")
 Source.json_cache.erase(synthetic_path);synthetic={};original_synthetic={}
 DirAccess.remove_absolute(synthetic_path);DirAccess.remove_absolute("user://native-memory-fixture")
 # Non-template public read_json keeps its prior mutable-cache contract.
 var fixture:String="user://native-source-mutable-fixture.json"
 var output:=FileAccess.open(fixture,FileAccess.WRITE);output.store_string('{"branch":{"value":1}}');output.close()
 var ordinary:Dictionary=Source.read_json(fixture)
 ordinary.branch.value=2
 ck(Source.read_json(fixture).branch.value==2,"ordinary read_json mutation semantics unchanged")
 Source.clear_caches();ordinary={};DirAccess.remove_absolute(fixture)
 print("NATIVE_SOURCE_MEMORY retained_bytes=",retained," active_roster=",ROSTER.size()," failures=",failures)
 quit(1 if failures else 0)
