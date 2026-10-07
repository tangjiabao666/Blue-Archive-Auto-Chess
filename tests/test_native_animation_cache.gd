extends SceneTree
func _initialize():call_deferred("run")
func run():
	var profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	var first=load("res://scripts/unit_view.gd").new();var second=load("res://scripts/unit_view.gd").new();root.add_child(first);root.add_child(second)
	first.setup({"id":0,"team":0,"cell":Vector2.ZERO,"range":3,"presentation":profiles.shiroko},{},1)
	second.setup({"id":1,"team":1,"cell":Vector2(1,0),"range":3,"presentation":profiles.shiroko},{},1)
	var key=first.player.get_animation_library_list()[0]
	var shared=first.player.get_animation_library(key)==second.player.get_animation_library(key)
	first.player.play(first.WALK);second.player.play(second.IDLE)
	var independent=first.player.current_animation!=second.player.current_animation
	print("NATIVE CACHE shared=",shared," independent_players=",independent)
	first.queue_free();second.queue_free();await process_frame;quit(0 if shared and independent else 1)
