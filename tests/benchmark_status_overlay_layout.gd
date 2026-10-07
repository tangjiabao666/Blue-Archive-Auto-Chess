extends SceneTree
## CPU-only pure layout timing; excludes rendering, actors, and simulation.
const Layout=preload("res://core/status_overlay_layout.gd")
const SAMPLES:=300
func _initialize():call_deferred("run")
func run():
	var layout=Layout.new()
	var bounds:=Rect2(8,112,984,530)
	var normal:Array=[];var dense:Array=[];var coincident:Array=[]
	for i in 12:
		normal.append({"id":i,"rect":Rect2(50+(i%4)*180,150+(i/4)*130,92,75)})
		dense.append({"id":i,"rect":Rect2(430+(i%4)*12,250+(i/4)*8,92,75)})
		coincident.append({"id":i,"rect":Rect2(430,250,92,75)})
	var scenarios:Array=[{"name":"normal_12","items":normal,"bounds":bounds},{"name":"dense_12","items":dense,"bounds":bounds},{"name":"coincident_12","items":coincident,"bounds":bounds},{"name":"impossible_12","items":coincident,"bounds":Rect2(400,250,200,150)}]
	var results:Dictionary={"scope":"CPU-only pure layout calls; not game FPS","samples_per_scenario":SAMPLES,"rectangle_size":[92,75],"candidate_count":layout._candidate_offsets(Vector2(92,75)).size(),"scenarios":{}}
	for scenario in scenarios:
		var expected:Dictionary=layout.arrange(scenario.items,scenario.bounds,11)
		for i in 20:layout.arrange(scenario.items,scenario.bounds,11)
		var samples:Array[int]=[];var total:=0
		for i in SAMPLES:
			var begin:int=Time.get_ticks_usec()
			var result:Dictionary=layout.arrange(scenario.items,scenario.bounds,11)
			var elapsed:int=Time.get_ticks_usec()-begin
			total+=elapsed;samples.append(elapsed)
			assert(result==expected,"pure layout output changed between calls")
		results.scenarios[scenario.name]=_summary(samples,total)
	# Both variants receive the same 300 slowly translated twelve-unit frames.
	# Input construction and assertions are excluded; call order alternates.
	var initial:Dictionary=layout.arrange(dense,bounds,11)
	var previous:Dictionary=initial
	var delta:=Vector2(0.125,0.0625)
	var moving_samples:Dictionary={"full_search":[],"preferred":[]}
	var moving_totals:Dictionary={"full_search":0,"preferred":0}
	for frame in SAMPLES:
		var full_items:Array=dense.duplicate(true)
		for item in full_items:item.rect=Rect2(item.rect.position+delta*(frame+1),item.rect.size)
		var preferred_items:Array=full_items.duplicate(true)
		var expected:Dictionary={}
		for item in preferred_items:
			item.preferred=Rect2(previous[item.id].position+delta,item.rect.size)
			expected[item.id]=Rect2(initial[item.id].position+delta*(frame+1),item.rect.size)
		var inputs:Dictionary={"full_search":full_items,"preferred":preferred_items}
		var order:Array=["full_search","preferred"] if frame%2==0 else ["preferred","full_search"]
		for variant in order:
			var begin:int=Time.get_ticks_usec()
			var result:Dictionary=layout.arrange(inputs[variant],bounds,11)
			var elapsed:int=Time.get_ticks_usec()-begin
			moving_totals[variant]+=elapsed;moving_samples[variant].append(elapsed)
			if variant=="preferred":assert(result==expected,"warm moving cluster changed relative geometry");previous=result
	for variant in moving_samples:results.scenarios["moving_12_"+variant]=_summary(moving_samples[variant],moving_totals[variant])
	print("STATUS_OVERLAY_LAYOUT_CPU ",JSON.stringify(results))
	quit()
func _summary(samples:Array,total:int)->Dictionary:
	samples.sort()
	return {"mean_ms":float(total)/samples.size()/1000.0,"median_ms":samples[samples.size()/2]/1000.0,"p95_ms":samples[int(samples.size()*0.95)]/1000.0,"max_ms":samples.back()/1000.0}
