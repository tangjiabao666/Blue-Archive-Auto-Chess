extends SceneTree
const Warmup=preload("res://scripts/render_warmup.gd")
func _initialize():call_deferred("run")
func run():
	var session=preload("res://core/game_session.gd").new()
	var canvas=CanvasLayer.new();root.add_child(canvas)
	var label=Label.new();label.text="正在准备四对四角色与技能着色器…";label.position=Vector2(30,30);canvas.add_child(label)
	await process_frame
	var warmup=Warmup.new();root.add_child(warmup)
	await warmup.run(session.profiles)
	print("PREVIEW_WARMUP=",JSON.stringify(Warmup.last_report))
	warmup.queue_free();canvas.queue_free()
	change_scene_to_file("res://tests/record_four_preview.tscn" if OS.get_environment("BLUE_A_RECORD")=="1" else "res://tests/four_combat_preview.tscn")
