extends SceneTree
class PreviewApp extends 'res://scripts/game_app.gd':
 func _evidence_root()->String:return 'res://evidence/mobile-preview'
var app
func _initialize():call_deferred('run')
func run():
 root.size=Vector2i(1320,600);root.title='Blue-A · 手机横屏试玩预览'
 app=PreviewApp.new();app.mobile_ui=true;app.new_game_mode='tactical_v1';app.persistence_enabled=false;root.add_child(app)
 while app.warming:await process_frame
 app.act({'type':'restart','seed':23})
 var p:Dictionary=app.session.rules._player_ref('p0');p.gold=100
 for key in ['asuna','asuna','asuna','yuuka','yuuka','yuuka','serika']:app.session.rules._acquire_one_star(p,key)
 app.session.preview_roster();app._refresh(true)
 while app.bench[0].icon==null:await process_frame
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute('res://evidence/mobile-preview')
 root.get_texture().get_image().save_png('res://evidence/mobile-preview/preparation.png')
 print('MOBILE_PREVIEW_READY')
