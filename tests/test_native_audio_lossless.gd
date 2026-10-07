extends SceneTree
func _initialize():
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/native-skill-sfx.json"))
	var fails:=0;var checked:=0
	for row in data.records:
		if not row.get("currentSimSelectable",false):continue
		var stream=load(row.resourcePath) as AudioStreamWAV
		if stream==null or stream.format!=AudioStreamWAV.FORMAT_16_BITS:
			fails+=1;printerr("Native audio must not be recompressed: ",row.clipName);continue
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(stream.data)
		if hash.finish().hex_encode()!=str(row.get("pcmDataSHA256","")):
			fails+=1;printerr("Imported PCM differs from source: ",row.clipName)
		checked+=1
	if checked!=data.records.filter(func(row):return row.get("currentSimSelectable",false)).size() or checked!=48:fails+=1
	print("NATIVE AUDIO LOSSLESS CHECKED=",checked," FAILURES=",fails);quit(1 if fails else 0)
