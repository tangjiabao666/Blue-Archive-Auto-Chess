extends RefCounted
## Normalize exported clip length from independently verified source durations.
## Returned deep copies may be modified without touching original resources.
static func normalized_copy(source: AnimationLibrary, durations: Dictionary, loops: Array = []) -> Dictionary:
	var library := AnimationLibrary.new()
	var warnings: Array[String] = []
	if source == null: return {"library":library,"warnings":["source library is null"]}
	for name in source.get_animation_list():
		var original: Animation = source.get_animation(name)
		var copy: Animation = original.duplicate(true)
		if name == "RESET":
			library.add_animation(name,copy)
			continue
		var duration = durations.get(String(name))
		var valid: bool = (duration is float or duration is int)
		if valid: valid = is_finite(float(duration)) and float(duration)>0
		var last_key := 0.0
		for track in range(copy.get_track_count()):
			for key in range(copy.track_get_key_count(track)):
				last_key = maxf(last_key,copy.track_get_key_time(track,key))
		if valid: valid = float(duration) + 0.0001 >= last_key
		if valid:
			copy.length = float(duration)
			copy.loop_mode = Animation.LOOP_LINEAR if String(name) in loops else Animation.LOOP_NONE
		else:
			warnings.append("%s: no valid verified duration, preserved original" % name)
		library.add_animation(name,copy)
	return {"library":library,"warnings":warnings}
