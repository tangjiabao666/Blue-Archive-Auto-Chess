extends Node3D
## Isolated clean academy-courtyard candidate. Visuals only: no gameplay/physics.
## Call configure(obstacles, half_size) after adding this node to the Stage.
## Omitting half_size preserves the original 13.2-unit academy courtyard.
## The Stage owns camera, lighting, combat, free placement and navigation.
const HALF_SIZE:float=6.6
const TALL_HEIGHT:float=1.05
const LOW_HEIGHT:float=0.42
const PALETTE={
	"court":Color("9db0bc"), "foundation":Color("547183"),
	"concrete":Color("d7e3df"), "edge":Color("edf2e7"),
	"blue":Color("426c86"), "paint":Color("dce6df"),
	"glass":Color("719bad"), "green":Color("7caaa1"),
	"accent":Color("d5b789"), "shadow":Color("8297a5")
}
var _materials:Dictionary={}
var _batches:Dictionary={}
var _primitive_count:int=0
var _layout_scale:float=1.0

func configure(obstacles:Array,half_size:float=HALF_SIZE)->void:
	for child in get_children():
		remove_child(child);child.queue_free()
	set_meta("playable_bounds",Rect2(-half_size,-half_size,half_size*2.0,half_size*2.0))
	var ground:=_group("Ground")
	# Expand only the court and perimeter in the horizontal plane. Cover and
	# contact shadows keep the authoritative world-space navigation footprint.
	_layout_scale=half_size/HALF_SIZE
	_build_ground(ground)
	_layout_scale=1.0
	_build_contact_shadows(ground,obstacles)
	var cover:=_group("Cover")
	for index in range(obstacles.size()):
		var obstacle:Dictionary=obstacles[index]
		var holder:=Node3D.new();holder.name="Obstacle_%02d"%index;cover.add_child(holder)
		var rect:Rect2=obstacle.rect
		var blocks:bool=obstacle.blocks_projectiles
		holder.set_meta("rect",rect);holder.set_meta("blocks_projectiles",blocks)
		holder.set_meta("height",TALL_HEIGHT if blocks else LOW_HEIGHT)
		_build_cover(holder,rect,blocks)
	var scenery:=_group("Scenery")
	_layout_scale=half_size/HALF_SIZE
	_build_north(scenery);_build_east(scenery);_build_foreground_edges(scenery)
	_layout_scale=1.0

func _group(label:String)->Node3D:
	var group:=Node3D.new();group.name=label;add_child(group);return group

func _build_ground(parent:Node3D)->void:
	# Playable top stays at y=0; horizontal layout scaling adds no collision.
	_begin()
	_box(Vector3(13.2,0.09,13.2),Vector3(0,-0.045,0),"court")
	_flush(parent,"PlayableSurface")
	_begin()
	_box(Vector3(13.8,0.12,13.8),Vector3(0,-0.15,0),"foundation")
	for side in [-1.0,1.0]:
		_box(Vector3(0.16,0.09,13.52),Vector3(side*6.7,-0.045,0),"edge")
		_box(Vector3(13.52,0.09,0.16),Vector3(0,-0.045,side*6.7),"edge")
	# Broad perimeter bands, not raised curbs or placement cells.
	for x in [-6.21,6.21]:
		_ground_rect(Rect2(x-0.18,-6.5,0.36,13.0),0.001,"foundation")
	for z in [-6.22,6.22]:
		_ground_rect(Rect2(-5.96,z-0.10,11.92,0.20),0.001,"paint")
	# Sparse L linework leaves the central action quiet and free of a grid.
	for x in [-5.89,5.89]:
		_ground_rect(Rect2(x-0.023,-5.32,0.046,10.64),0.002,"paint")
		for z in [-5.32,5.32]:
			_ground_rect(Rect2(x-0.49 if x>0 else x,z-0.023,0.49,0.046),0.002,"paint")
	for x in [-6.21,6.21]:
		for z in [-0.36,0.0,0.36]:
			_ground_rect(Rect2(x-0.13,z-0.06,0.26,0.12),0.003,"edge")
	for x in [-4.95,3.45]:
		_ground_rect(Rect2(x,0.337,1.5,0.026),0.002,"paint")
	_flush(parent,"CourtDetails")

func _build_contact_shadows(parent:Node3D,obstacles:Array)->void:
	# Opaque unshaded floor paint. No alpha blending/lights/postprocess.
	_begin()
	for obstacle in obstacles:
		var rect:Rect2=obstacle.rect
		var height:float=TALL_HEIGHT if obstacle.blocks_projectiles else LOW_HEIGHT
		var shadow:Rect2=rect.grow(0.045)
		shadow.size+=Vector2(0.14,0.18)*height
		_ground_rect(shadow,0.004,"shadow")
	_flush(parent,"ContactShadows")

func _build_cover(parent:Node3D,rect:Rect2,blocks:bool)->void:
	_begin()
	var h:float=TALL_HEIGHT if blocks else LOW_HEIGHT
	var center:Vector2=rect.get_center()
	# The plinth retains the exact supplied collision footprint.
	_box(Vector3(rect.size.x,0.10,rect.size.y),Vector3(center.x,0.05,center.y),"blue")
	var body:=rect.grow(-0.018 if blocks else -0.012)
	_box(Vector3(body.size.x,h-0.24,body.size.y),Vector3(center.x,(h-0.04)*0.5,center.y),"concrete")
	_prism(body,h-0.14,h-0.065,0.0,0.048 if blocks else 0.03,"concrete")
	var cap:=rect.grow(-0.04 if blocks else -0.024)
	if blocks and rect.size.y>rect.size.x:
		# Split cap: a visible top inset without floating paint or z-fighting.
		var rim:float=cap.size.x*0.22
		var end:float=cap.size.y*0.12
		for side in [-1.0,1.0]:
			_box(Vector3(rim,0.065,cap.size.y),Vector3(center.x+side*(cap.size.x-rim)*0.5,h-0.0325,center.y),"edge")
			_box(Vector3(cap.size.x-rim*2.0,0.065,end),Vector3(center.x,h-0.0325,center.y+side*(cap.size.y-end)*0.5),"edge")
		_box(Vector3(cap.size.x-rim*2.0,0.065,cap.size.y-end*2.0),Vector3(center.x,h-0.0325,center.y),"blue")
	else:
		_box(Vector3(cap.size.x,0.065,cap.size.y),Vector3(center.x,h-0.0325,center.y),"edge")
	if rect.size.y>rect.size.x:
		for side in [-1.0,1.0]:
			var x:float=center.x+side*(rect.size.x*0.5-0.017)
			_box(Vector3(0.010,h*0.54,rect.size.y*0.69),Vector3(x,h*0.45,center.y),"blue")
			_box(Vector3(0.012,0.024,rect.size.y*0.61),Vector3(x+side*0.001,h*0.66,center.y),"edge")
			for fraction in [-0.205,0.0,0.205]:
				_box(Vector3(0.012,0.045,rect.size.y*0.094),Vector3(x+side*0.001,h*0.30,center.y+rect.size.y*fraction),"concrete")
	else:
		for side in [-1.0,1.0]:
			var z:float=center.y+side*(rect.size.y*0.5-0.011)
			_box(Vector3(rect.size.x*0.78,h*0.25,0.010),Vector3(center.x,h*0.43,z),"blue")
			for fraction in [-0.338,0.338]:
				_box(Vector3(rect.size.x*0.028,h*0.28,0.012),Vector3(center.x+rect.size.x*fraction,h*0.43,z),"edge")
	parent.set_meta("primitive_count",_primitive_count)
	_flush(parent,"Cover")

func _build_north(parent:Node3D)->void:
	var north:=Node3D.new();north.name="NorthAcademy";parent.add_child(north)
	_begin()
	_box(Vector3(15.0,0.12,3.0),Vector3(0,-0.10,-8.4),"concrete")
	_box(Vector3(13.4,0.15,0.22),Vector3(0,0.025,-7.13),"edge")
	for x in [-6.25,-2.25,2.25,6.25]:
		_box(Vector3(0.34,1.95,0.50),Vector3(x,0.975,-8.8),"concrete")
		_box(Vector3(0.37,0.16,0.53),Vector3(x,0.08,-8.8),"blue")
	_box(Vector3(13.25,0.25,0.68),Vector3(0,2.0,-8.8),"concrete")
	_box(Vector3(13.4,0.075,0.74),Vector3(0,2.15,-8.8),"edge")
	_box(Vector3(13.1,0.035,0.028),Vector3(0,1.91,-8.443),"blue")
	for x in [-4.25,0.0,4.25]:
		_box(Vector3(3.25,1.46,0.06),Vector3(x,0.96,-9.2),"glass")
		_box(Vector3(3.32,0.14,0.25),Vector3(x,0.15,-9.12),"concrete")
		for dx in [-0.79,0.79]:
			_box(Vector3(0.055,1.46,0.12),Vector3(x+dx,0.96,-9.15),"edge")
		_box(Vector3(3.25,0.055,0.12),Vector3(x,1.35,-9.15),"edge")
	# Warm canopy accent, deliberately no invented logo or branding.
	_box(Vector3(1.4,0.20,0.05),Vector3(0,1.99,-8.435),"blue")
	_box(Vector3(0.78,0.045,0.056),Vector3(0,2.0,-8.43),"accent")
	for x in [-5.75,5.75]:
		_box(Vector3(0.30,0.55,0.20),Vector3(x,0.30,-7.75),"blue")
		_box(Vector3(0.23,0.10,0.22),Vector3(x,0.54,-7.75),"accent")
	_flush(north,"North")

func _build_east(parent:Node3D)->void:
	var east:=Node3D.new();east.name="EastTerrace";parent.add_child(east)
	_begin()
	_box(Vector3(2.7,0.12,13.6),Vector3(8.35,-0.10,0),"concrete")
	_box(Vector3(0.22,0.15,13.4),Vector3(7.13,0.025,0),"edge")
	_box(Vector3(0.30,0.69,11.2),Vector3(8.90,0.345,0),"concrete")
	_box(Vector3(0.38,0.055,11.3),Vector3(8.90,0.7175,0),"blue")
	for z in [-3.2,3.2]:
		_box(Vector3(0.67,0.45,1.7),Vector3(9.15,0.225,z),"concrete")
		_prism(Rect2(8.855,z-0.79,0.59,1.58),0.45,0.71,0.0,0.055,"green")
		_box(Vector3(0.59,0.055,1.58),Vector3(9.15,0.735,z),"green")
	for z in [-5.62,5.62]:
		_box(Vector3(0.43,1.0,0.43),Vector3(8.9,0.50,z),"concrete")
		_box(Vector3(0.34,0.06,0.34),Vector3(8.9,1.03,z),"edge")
	for z in [-4.5,-1.5,1.5,4.5]:
		_box(Vector3(0.012,0.30,1.20),Vector3(8.744,0.40,z),"blue")
	_flush(east,"East")

func _build_foreground_edges(parent:Node3D)->void:
	# No tall objects in the camera-facing southwest foreground.
	var south:=Node3D.new();south.name="SouthApron";parent.add_child(south)
	_begin();_box(Vector3(13.6,0.08,0.55),Vector3(0,-0.08,7.1),"foundation");_flush(south,"South")
	var west:=Node3D.new();west.name="WestApron";parent.add_child(west)
	_begin();_box(Vector3(0.55,0.08,13.6),Vector3(-7.1,-0.08,0),"foundation");_flush(west,"West")

func _begin()->void:
	_batches.clear();_primitive_count=0

func _material(key:String)->StandardMaterial3D:
	if not _materials.has(key):
		var material:=StandardMaterial3D.new()
		material.albedo_color=PALETTE[key];material.roughness=0.92
		if key in ["paint","shadow"]:material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key]=material
	return _materials[key]

func _ground_rect(rect:Rect2,y:float,key:String)->void:
	_quad(Vector3(rect.position.x,y,rect.position.y),Vector3(rect.end.x,y,rect.position.y),Vector3(rect.end.x,y,rect.end.y),Vector3(rect.position.x,y,rect.end.y),key)

func _box(size:Vector3,at:Vector3,material:String)->void:
	var half:=size*0.5
	var p:=at-half;var q:=at+half
	_hexahedron([
		Vector3(p.x,p.y,p.z),Vector3(q.x,p.y,p.z),Vector3(q.x,p.y,q.z),Vector3(p.x,p.y,q.z),
		Vector3(p.x,q.y,p.z),Vector3(q.x,q.y,p.z),Vector3(q.x,q.y,q.z),Vector3(p.x,q.y,q.z)
	],material)

func _prism(rect:Rect2,bottom:float,top:float,bottom_inset:float,top_inset:float,material:String)->void:
	var b:=rect.grow(-bottom_inset);var t:=rect.grow(-top_inset)
	_hexahedron([
		Vector3(b.position.x,bottom,b.position.y),Vector3(b.end.x,bottom,b.position.y),Vector3(b.end.x,bottom,b.end.y),Vector3(b.position.x,bottom,b.end.y),
		Vector3(t.position.x,top,t.position.y),Vector3(t.end.x,top,t.position.y),Vector3(t.end.x,top,t.end.y),Vector3(t.position.x,top,t.end.y)
	],material)

func _hexahedron(v:Array,material:String)->void:
	_primitive_count+=1
	for face in [[0,1,2,3],[4,7,6,5],[0,4,5,1],[3,2,6,7],[0,3,7,4],[1,5,6,2]]:
		_quad(v[face[0]],v[face[3]],v[face[2]],v[face[1]],material)

func _quad(a:Vector3,b:Vector3,c:Vector3,d:Vector3,material:String)->void:
	if _layout_scale!=1.0:
		var scale_xz:=Vector3(_layout_scale,1.0,_layout_scale)
		a*=scale_xz;b*=scale_xz;c*=scale_xz;d*=scale_xz
	if not _batches.has(material):_batches[material]={"vertices":PackedVector3Array(),"normals":PackedVector3Array()}
	var data:Dictionary=_batches[material]
	var normal:Vector3=(c-a).cross(b-a).normalized()
	for vertex in [a,b,c,a,c,d]:
		data.vertices.append(vertex);data.normals.append(normal)

func _flush(parent:Node3D,label:String)->void:
	for key in _batches:
		var data:Dictionary=_batches[key]
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=data.vertices;arrays[Mesh.ARRAY_NORMAL]=data.normals
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var node:=MeshInstance3D.new()
		node.name=label if _batches.size()==1 else label+"_"+key
		node.mesh=mesh;node.material_override=_material(key)
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
	_batches.clear()
