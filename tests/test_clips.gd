extends SceneTree
const Adapter=preload("res://core/clip_adapter.gd")
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize()->void:
	var source=AnimationLibrary.new()
	var clip=Animation.new();clip.length=5.5
	var track=clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track,NodePath("Unit:value"))
	clip.track_insert_key(track,0.0,0);clip.track_insert_key(track,0.63,1)
	source.add_animation("Attack_Start",clip)
	var result=Adapter.normalized_copy(source,{"Attack_Start":0.63},["Attack_Start"])
	ck(result.library!=null,"produces animation library")
	if result.library==null:quit(1);return
	var copy=result.library.get_animation("Attack_Start")
	ck(is_equal_approx(copy.length,0.63),"clips to verified original duration")
	ck(copy.loop_mode==Animation.LOOP_LINEAR,"applies requested loop")
	ck(source.get_animation("Attack_Start").length==5.5 and clip.loop_mode==Animation.LOOP_NONE,"never mutates original")
	copy.track_set_key_value(0,0,99)
	ck(clip.track_get_key_value(0,0)==0,"keyframes deeply isolated")
	var missing=Adapter.normalized_copy(source,{})
	ck(missing.warnings.size()==1 and missing.library.get_animation("Attack_Start").length==5.5,"missing evidence preserves original with warning")
	for value in [-1.0,0.0,NAN,INF,"bad",0.1]:
		var bad=Adapter.normalized_copy(source,{"Attack_Start":value})
		ck(bad.warnings.size()==1 and bad.library.get_animation("Attack_Start").length==5.5,"invalid or key-truncating duration refused")
	print("CLIP FAILURES=",fails);quit(1 if fails else 0)
