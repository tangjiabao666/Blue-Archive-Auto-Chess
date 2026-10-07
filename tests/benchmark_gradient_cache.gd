extends SceneTree
const Current=preload("res://vfx/native_curves.gd")
const Source=preload("res://vfx/native_source.gd")
var gradients:Array=[]
func _initialize():
	var baseline=GDScript.new();baseline.source_code=FileAccess.get_file_as_string("res://tests/fixtures/native_curves_before_cache.gd")
	if baseline.reload()!=OK:quit(1);return
	for key in ["shiroko","hoshino","hina","aru","yuuka","aris","serika"]:_collect(Source.read_json("res://data/effects/"+key+"/visual-templates.json"))
	gradients=gradients.slice(0,160)
	var old_us:=0;var new_us:=0;var bad:=0
	for repeat_index in range(200):
		var t:float=(repeat_index%100)/100.0
		for g in gradients:
			var started=Time.get_ticks_usec();var old:Color=baseline.gradient(g,t);old_us+=Time.get_ticks_usec()-started
			started=Time.get_ticks_usec();var fresh:Color=Current.gradient(g,t);new_us+=Time.get_ticks_usec()-started
			if old!=fresh:bad+=1
	print("GRADIENT BENCH baseline_us=",old_us," cached_us=",new_us," parity_failures=",bad," cache=",Current.gradient_cache_stats());quit(0 if bad==0 else 1)
func _collect(v:Variant):
	if v is Dictionary:
		if v.has("m_NumColorKeys"):gradients.append(v)
		for key in v:_collect(v[key])
	elif v is Array:
		for item in v:_collect(item)
