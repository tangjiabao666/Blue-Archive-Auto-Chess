extends Node3D
var local_team:int=0
const Volumes=preload('res://core/attack_volumes.gd')
var _handles:Dictionary={}
var geometry_builds:=0
func tracked_count()->int:return _handles.size()
func reset()->void:
 for entry in _handles.values():entry.node.visible=false;entry.node.queue_free()
 _handles.clear()
func update_volumes(volumes:Array,at:float)->void:
 if not is_finite(at):return
 var live:Dictionary={}
 for volume in volumes:
  if volume.ability=='normal' or volume.impacts.is_empty():continue
  var end:float=volume.impacts[-1].due*0.05
  if at>=end:continue
  var id:int=volume.id;live[id]=true
  if not _handles.has(id):_handles[id]=_build(volume)
  var entry:Dictionary=_handles[id]
  var start:float=volume.cast_start_tick*0.05
  var progress:float=clampf((at-start)/maxf(0.05,end-start),0,1)
  var color:Color=Color(1.0,0.2,0.23) if volume.team!=local_team else Color(0.1,0.75,1.0)
  color.a=0.12+0.10*progress;entry.material.albedo_color=color
 for id in _handles.keys():
  if not live.has(id):_handles[id].node.visible=false;_handles[id].node.queue_free();_handles.erase(id)
func _build(volume:Dictionary)->Dictionary:
 var node:=MeshInstance3D.new();node.name='AttackWarning_'+str(volume.id)
 var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.cull_mode=BaseMaterial3D.CULL_DISABLED
 material.render_priority=2;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var vertices:=PackedVector3Array();var indices:=PackedInt32Array()
 for polygon in Volumes.outline(volume):
  var base:int=vertices.size()
  for point in polygon:vertices.append(Vector3(point.x,0.045,point.y))
  for index in Geometry2D.triangulate_polygon(polygon):indices.append(base+index)
 var mesh:=ArrayMesh.new()
 if not vertices.is_empty() and not indices.is_empty():
  var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=indices
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 node.mesh=mesh;node.material_override=material;add_child(node);geometry_builds+=1
 return {'node':node,'material':material}
