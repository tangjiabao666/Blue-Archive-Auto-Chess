extends SceneTree
const Fixtures=preload("res://tests/normal_target_fixtures.gd")
func _initialize() -> void:
	var result := {"source_commit":"4990a6be5a54e856eab415b3e2f1a6ac5d375e6b","natural":{},"diagnostics":{},"skills":{}}
	for count in [4,5,6]:
		for star in [1,2]:
			var name: String="%dv%d-star%d"%[count,count,star]
			result.natural[name]=Fixtures.natural_trace(count,star)
			print("CAPTURE ",name," ",result.natural[name])
	for name in Fixtures.DIAGNOSTICS:result.diagnostics[name]=Fixtures.diagnostic(name)
	for key in Fixtures.KEYS:
		for ability in ["basic","ex"]:result.skills[key+":"+ability]=Fixtures.skill_dispatch(key,ability)
	FileAccess.open(Fixtures.BASELINE,FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("CAPTURED accepted baseline: 6 natural traces, 6 diagnostic traces, 28 skill dispatch states")
	quit()
