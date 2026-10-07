extends SceneTree
func _initialize():call_deferred("run")
func run():
 var world=Node3D.new();root.add_child(world)
 var environment=WorldEnvironment.new();var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("cad7e0");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=0.6;environment.environment=env;world.add_child(environment)
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-30,0);light.light_energy=0.8;world.add_child(light)
 var floor_view=MeshInstance3D.new();var floor_mesh=PlaneMesh.new();floor_mesh.size=Vector2(4,3);floor_view.mesh=floor_mesh;var material=StandardMaterial3D.new();material.albedo_color=Color("a9c3cc");floor_view.material_override=material;world.add_child(floor_view)
 var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.4;camera.position=Vector3(-2,3,4);world.add_child(camera);camera.look_at(Vector3.ZERO);camera.current=true
 var mines=load("res://scripts/native_ground_mines.gd").new();world.add_child(mines);mines.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json")));mines.reset(42)
 var units=[{"id":1,"character_id":"mutsuki","team":0}]
 for i in range(3):mines.consume({"type":"mine_placed","mine_id":i,"actor_id":1,"tick":0,"generation":42,"event_id":str(i),"cell":Vector2((i-1)*0.8,0),"expires_tick":200},units)
 mines.update_time(1.0)
 await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://evidence/native-ground-mines-visual.png")
 print("NATIVE MINE SNAPSHOT ",mines.diagnostics());quit()
