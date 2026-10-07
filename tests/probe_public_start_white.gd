extends SceneTree
## Diagnostic isolation only; production code/source art are unchanged.
const Player=preload('res://vfx/native_effect_player.gd')
func anchor(_binding:Dictionary,_event:Dictionary,_at:float,x:float)->Transform3D:return Transform3D(Basis.IDENTITY,Vector3(x,0,0))
func _initialize()->void:call_deferred('run')
func run()->void:
 root.size=Vector2i(1440,650)
 var world:=Node3D.new();root.add_child(world)
 var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.65,.7,.73);environment.environment=env;world.add_child(environment)
 var cam:=Camera3D.new();world.add_child(cam);cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=10;cam.position=Vector3(-3,3.5,11);cam.look_at(Vector3.ZERO);cam.current=true
 var canvas:=CanvasLayer.new();world.add_child(canvas)
 var label:=Label.new();label.text='DIAGNOSTIC: original Public_Start                  flare1 (3) isolated                       mask RGB (same cutoff)\nSame original prefab at 0.35 seconds. Isolation/color diagnostic only.';label.position=Vector2(25,15);label.add_theme_color_override('font_color',Color.BLACK);canvas.add_child(label)
 for col in range(3):
  var p=Player.new();world.add_child(p)
  p.spawn('res://data/effects/aru/visual-templates.json#FX_Public_Start',942,0.0,anchor.bind((col-1)*3.7),1.0);p.update_time(.35)
  for effect in p._effects:
   for layer in effect.layers:
    for item in layer.particles:
     if col>0 and not str(layer.path).ends_with('/flare1 (3)'):item.node.visible=false;continue
     if col==2:
      var m:ShaderMaterial=item.material;var shader:=Shader.new();shader.code=m.shader.code.replace('ALBEDO = SV_Target0.rgb;','ALBEDO = vec3(texture(_Tex_Mask, UV * uv_sheet.xy + uv_sheet.zw).r);');m.shader=shader
 if DisplayServer.get_name()=='headless':print('WHITE_PROBE initialized; render not run');quit();return
 for frame in range(5):await process_frame
 await RenderingServer.frame_post_draw
 var out:='res://evidence/probe-public-start-white.png';DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
 var err:int=root.get_texture().get_image().save_png(out);print('WHITE_PROBE_IMAGE ',out,' error=',err);quit(err)
