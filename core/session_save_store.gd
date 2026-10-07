extends RefCounted
## Bounded JSON checkpoints only. No Variant/object deserialization is used.
## Writes verify a sibling temporary file before replacing the main checkpoint;
## a valid previous main is retained in .bak. Reads never modify either file.
const Session=preload("res://core/game_session.gd")
const DEFAULT_PATH:="user://session-save.json"
const MAX_BYTES:=Session.MAX_SAVE_BYTES

static func write_save(payload:Dictionary,path:String=DEFAULT_PATH)->Dictionary:
	if path.is_empty():return _failure("invalid_save_path")
	var valid:Dictionary=_validate(payload)
	if not valid.ok:return valid
	var encoded:String=JSON.stringify(payload,"",true,true)
	if encoded.to_utf8_buffer().size()>MAX_BYTES:return _failure("save_too_large")
	var staged:Dictionary=_write_verified(path+".tmp",encoded)
	if not staged.ok:return staged
	var current:Dictionary=_read_one(path)
	if current.ok:
		var backed_up:Dictionary=_write_verified(path+".bak.tmp",current.text)
		if not backed_up.ok:return _failure("save_backup_failed: "+backed_up.error)
		var backup_error:Error=DirAccess.rename_absolute(path+".bak.tmp",path+".bak")
		if backup_error!=OK:return _failure("save_backup_replace_failed: "+error_string(backup_error))
	elif current.error=="save_open_failed":
		# An unreadable existing save must not be overwritten without a backup.
		return _failure("save_backup_failed: unreadable_current_save")
	# A corrupt main never replaces a known-good previous backup.
	var replaced:Error=DirAccess.rename_absolute(path+".tmp",path)
	if replaced!=OK:return _failure("save_replace_failed: "+error_string(replaced))
	return {"ok":true,"error":""}

static func read_save(path:String=DEFAULT_PATH)->Dictionary:
	if path.is_empty():return _failure("invalid_save_path")
	var current:Dictionary=_read_one(path)
	if current.ok:return {"ok":true,"error":"","data":current.data,"recovered":false,"source_path":path,"warning":""}
	var previous:Dictionary=_read_one(path+".bak")
	if previous.ok:
		return {"ok":true,"error":"","data":previous.data,"recovered":true,"source_path":path+".bak",
			"warning":"previous_checkpoint_recovered: "+current.error}
	if current.error=="save_not_found" and previous.error=="save_not_found":return _failure("save_not_found")
	return _failure("save_unavailable: "+current.error+"; backup: "+previous.error)

static func _validate(payload:Variant)->Dictionary:
	if not payload is Dictionary:return _failure("invalid_save_schema")
	var candidate=Session.new()
	var checked:Dictionary=candidate.restore_save(payload)
	return {"ok":checked.ok,"error":checked.error}

static func _read_one(path:String)->Dictionary:
	if not FileAccess.file_exists(path):return _failure("save_not_found")
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null:return _failure("save_open_failed")
	var length:int=file.get_length()
	if length<=0 or length>MAX_BYTES:
		file.close();return _failure("save_too_large" if length>MAX_BYTES else "empty_save")
	var bytes:PackedByteArray=file.get_buffer(length)
	file.close()
	if bytes.size()!=length:return _failure("save_read_failed")
	var contents:String=bytes.get_string_from_utf8()
	var parser=JSON.new()
	if parser.parse(contents)!=OK:return _failure("invalid_save_json")
	var checked:Dictionary=_validate(parser.data)
	if not checked.ok:return checked
	return {"ok":true,"error":"","data":parser.data,"text":contents}

static func _write_verified(path:String,contents:String)->Dictionary:
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return _failure("save_write_failed: "+error_string(FileAccess.get_open_error()))
	file.store_string(contents);file.flush()
	var written:Error=file.get_error()
	file.close()
	if written!=OK:return _failure("save_write_failed: "+error_string(written))
	var verified:Dictionary=_read_one(path)
	if not verified.ok:return _failure("save_verification_failed: "+verified.error)
	if verified.text!=contents:return _failure("save_verification_failed: changed_bytes")
	return {"ok":true,"error":""}

static func _failure(message:String)->Dictionary:
	return {"ok":false,"error":message}
