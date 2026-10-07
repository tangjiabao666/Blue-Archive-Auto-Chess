extends SceneTree
func _initialize():call_deferred("run")
func run():
 preload("res://scripts/render_warmup.gd").completed=true
 var app=load("res://scripts/gameplay.tscn").instantiate();root.add_child(app);await process_frame;app.set_process(false)
 root.title="Blue-A | Shop odds UI acceptance"
 app.act({"type":"restart","seed":17})
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://evidence/level-shop-odds/level4.png")
 app.act({"type":"buy_offer","slot":99})
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://evidence/level-shop-odds/notice.png")
 app.act({"type":"buy_xp"});app.act({"type":"buy_xp"})
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://evidence/level-shop-odds/level5.png")
 print("SHOP_ODDS_NATIVE ",app.shop_odds_label.text," tooltip=",app.shop_odds_label.tooltip_text)
 app.queue_free();await process_frame;quit()
