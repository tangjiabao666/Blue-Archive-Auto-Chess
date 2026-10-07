extends SceneTree
## Diagnostic only. Does not mutate source resources or production scripts.
## Top row: Aris hit prefab; bottom row: Aris shot prefab at 0.2 s.
## Columns: untouched / front-green back-magenta / diagnostic inverted FRONT_FACING.
const Player=preload('res://vfx/native_effect_player.gd')
var players:Array=[]
func anchor(_binding:Dictionary,_event:Dictionary,_at:float,offset:Vector3)->Transform3D:
 return Transform3D(Basis.IDENTITY,offset)
func _initialize()->void:call_deferred('run')
func run()->void:
 root.size=Vector2i(1440,900)
 var world:=Node3D.new();root.add_child(world)
 var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(0.65,0.7,0.73);environment.environment=env;world.add_child(environment)
 var cam:=Camera3D.new();world.add_child(cam);cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=11.8;cam.position=Vector3(0,4.5,11);cam.look_at(Vector3(0,0,0));cam.current=true
 var canvas:=CanvasLayer.new();world.add_child(canvas)
 var label:=Label.new();label.text='DIAGNOSTIC: original                       front GREEN / back MAGENTA              inverted FRONT_FACING\nTop: Aris hit rings     Bottom: Aris shot rings     Source times: 0.2 s';label.position=Vector2(30,15);label.add_theme_color_override('font_color',Color.BLACK);canvas.add_child(label)
 for row in range(2):
  for col in range(3):
   var p=Player.new();world.add_child(p);players.append(p)
   var selector:String='FX_Aris_Original_Ex01_Motion_Hit_Start' if row==0 else 'FX_Aris_Original_Ex01_Motion_Shot'
   p.spawn('res://data/effects/aris/visual-templates.json#'+selector,942,0.0,anchor.bind(Vector3((col-1)*4.1,0,(-1 if row==0 else 1)*2.0)),1.0)
   p.update_time(0.2)
   for effect in p._effects:
    for layer in effect.layers:
     for item in layer.particles:
      var material:ShaderMaterial=item.material
      var descriptor:Dictionary=material.get_meta('native_source_descriptor',{})
      if str(descriptor.get('shader',{}).get('name',''))!='DSFX/FX_SHADER_Step_2side_0':continue
      if col==0 and item.node.visible:
       print('FACE_PROBE ',layer.path,' determinant=',item.node.global_basis.determinant(),' scale=',item.node.global_basis.get_scale(),' custom1=',material.get_shader_parameter('custom1'),' color=',material.get_shader_parameter('particle_color'))
      if col==0:continue
      var modified:Shader=Shader.new();var code:String=material.shader.code
      if col==1:code=code.replace('ALBEDO = SV_Target0.rgb;','ALBEDO = FRONT_FACING ? vec3(0.0,1.0,0.0) : vec3(1.0,0.0,1.0);')
      else:code=code.replace('FRONT_FACING ?','(!FRONT_FACING) ?')
      modified.code=code;material.shader=modified
 if DisplayServer.get_name()=='headless':
  print('Headless: determinant diagnostics only; no rendered result.');quit();return
 for frame in range(5):await process_frame
 await RenderingServer.frame_post_draw
 var out:String=OS.get_environment('DARK_FACE_OUT')
 if out.is_empty():out='res://evidence/probe-dark-face.png'
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
 var err:int=root.get_texture().get_image().save_png(out);print('FACE_PROBE_IMAGE ',out,' error=',err)
 quit(err)
