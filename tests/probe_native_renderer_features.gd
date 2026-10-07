extends SceneTree
## Serial read-only inventory of source renderer fields reaching active EX/basic layers.
const Player=preload("res://vfx/native_effect_player.gd")
const Source=preload("res://vfx/native_source.gd")
const Curves=preload("res://vfx/native_curves.gd")
const EVENTS="res://data/effects/battle-events-compact.json"
func anchor(_binding:Dictionary,_event:Dictionary,_at:float)->Transform3D:return Transform3D.IDENTITY
func _initialize()->void:call_deferred("run")
func run()->void:
 var compact:Dictionary=Source.read_json(EVENTS)
 var output:Dictionary={"characters":{},"layer_rows":[]}
 for character in compact.activeRoster:
  var unique:Dictionary={};var summary:Dictionary={"layer_instances":0,"source_layers":0,"pivot":0,"flip":0,"pivot_mesh":0,"flip_mesh":0,"pivot_and_flip":0,"zero_schedule":0,"scheduled_particles":0}
  for kind in ["ex","basic"]:
   var player=Player.new();root.add_child(player)
   player.play_timeline(EVENTS,character,kind,0.0,anchor)
   for effect in player._effects:
    var occurrence:Dictionary={}
    for layer in effect.layers:
     summary.layer_instances+=1
     occurrence[layer.path]=int(occurrence.get(layer.path,0))+1
     var key:String=effect.prefab+":"+layer.path+":"+str(occurrence[layer.path])
     if unique.has(key):continue
     unique[key]=true;summary.source_layers+=1
     var pivot:Vector3=Curves.unity_vector(layer.render.get("m_Pivot",{}))
     var flip:Vector3=Curves.unity_vector(layer.render.get("m_Flip",{}))
     var hp:bool=not pivot.is_zero_approx();var hf:bool=not flip.is_zero_approx()
     if hp:summary.pivot+=1
     if hf:summary.flip+=1
     if hp and hf:summary.pivot_and_flip+=1
     if hp and layer.mode==4:summary.pivot_mesh+=1
     if hf and layer.mode==4:summary.flip_mesh+=1
     if layer.particles.is_empty():summary.zero_schedule+=1
     summary.scheduled_particles+=layer.particles.size()
     var row:Dictionary={"character":character,"kind":kind,"prefab":effect.prefab,"path":layer.path,"occurrence":occurrence[layer.path],"mode":layer.mode,"pivot":layer.render.get("m_Pivot",{}),"flip":layer.render.get("m_Flip",{}),"scheduled":layer.particles.size(),"billboard":layer.billboard}
     if hp or hf:output.layer_rows.append(row)
   player.free();Player._material_cache.clear();Source.clear_caches()
  output.characters[character]=summary
  print(character," ",JSON.stringify(summary))
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/native-mesh-flip"))
 FileAccess.open("res://evidence/native-mesh-flip/source-feature-inventory.json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
 quit()
