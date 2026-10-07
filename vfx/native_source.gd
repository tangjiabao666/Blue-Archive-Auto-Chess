extends RefCounted
static var json_cache: Dictionary={}
static var mesh_cache: Dictionary={}

static func read_json(path: String)->Dictionary:
 if json_cache.has(path):return json_cache[path]
 if not FileAccess.file_exists(path):return {}
 var raw: String=FileAccess.get_file_as_string(path)
 # Python's extractor preserves infinite slopes. JSON itself forbids infinities;
 # finite sentinels retain stepped tangents in Curves without destroying fields.
 var rx:=RegEx.new();rx.compile("(?<=[:,\\[\\s])(-?Infinity|NaN)(?=[,}\\]\\s])")
 var tokens: Dictionary={}
 for token in rx.search_all(raw):tokens[token.get_string()]=true
 for value in tokens:
  raw=raw.replace(value,"-1e30" if value=="-Infinity" else "1e30" if value=="Infinity" else "0.0")
 var result=JSON.parse_string(raw)
 if not result is Dictionary:return {}
 # Source templates are immutable; exact repeated module/curve trees share memory.
 # Other JSON callers keep the historical mutable cached-dictionary contract.
 if path.get_file()=="visual-templates.json":result=_intern_source_tree(result,{})
 json_cache[path]=result
 return result

static func _intern_source_tree(value: Variant,pool: Dictionary)->Variant:
 if value is Dictionary:
  for key in value:value[key]=_intern_source_tree(value[key],pool)
 elif value is Array:
  for index in value.size():value[index]=_intern_source_tree(value[index],pool)
 else:return value
 # Hash lookup is only a candidate search. Exact encoding preserves float bits,
 # dictionary order, and types even when Godot equality considers values equal.
 # Pool lifetime is one file: only source-referenced containers remain resident.
 var key: String=str(typeof(value))+":"+str(value.hash())
 var bucket: Array=pool.get(key,[])
 for candidate in bucket:
  if candidate==value and var_to_bytes(candidate)==var_to_bytes(value):return candidate
 # Shared descendants must never be changed accidentally by another emitter.
 # Existing adapters explicitly duplicate parameters before any mutation.
 value.make_read_only()
 bucket.append(value);pool[key]=bucket
 return value

static func reference_key(ref: Dictionary)->String:
 return str(ref.get("cab",""))+"/"+str(ref.get("pathId",""))

static func find_prefab(data: Dictionary, selector: String)->Dictionary:
 for prefab in data.get("prefabs",[]):
  if prefab.get("name")==selector or reference_key(prefab.get("source",{}))==selector:return prefab
 return {}

static func obj_mesh(path: String)->ArrayMesh:
 if mesh_cache.has(path):return mesh_cache[path]
 if not FileAccess.file_exists(path):return null
 var positions: Array[Vector3]=[];var normals: Array[Vector3]=[];var uvs: Array[Vector2]=[]
 var out_positions:=PackedVector3Array();var out_normals:=PackedVector3Array();var out_uvs:=PackedVector2Array();var indices:=PackedInt32Array()
 var tuples: Dictionary={}
 for row in FileAccess.get_file_as_string(path).split("\n"):
  var bits: PackedStringArray=row.strip_edges().split(" ",false)
  if bits.is_empty():continue
  match bits[0]:
   "v":
    if bits.size()>=4:positions.append(Vector3(-float(bits[1]),float(bits[2]),-float(bits[3])))
   "vn":
    if bits.size()>=4:normals.append(Vector3(-float(bits[1]),float(bits[2]),-float(bits[3])))
   "vt":
    if bits.size()>=3:uvs.append(Vector2(float(bits[1]),float(bits[2])))
   "f":
    var face: Array[int]=[]
    for token in bits.slice(1):
     if not tuples.has(token):
      var components: PackedStringArray=token.split("/")
      var vi: int=int(components[0]);vi=vi-1 if vi>0 else positions.size()+vi
      if vi<0 or vi>=positions.size():continue
      var uv:=Vector2.ZERO;var normal:=Vector3.UP
      if components.size()>1 and not components[1].is_empty():
       var ti: int=int(components[1]);ti=ti-1 if ti>0 else uvs.size()+ti
       if ti>=0 and ti<uvs.size():uv=uvs[ti]
      if components.size()>2 and not components[2].is_empty():
       var ni: int=int(components[2]);ni=ni-1 if ni>0 else normals.size()+ni
       if ni>=0 and ni<normals.size():normal=normals[ni]
      tuples[token]=out_positions.size();out_positions.append(positions[vi]);out_normals.append(normal);out_uvs.append(uv)
     face.append(tuples[token])
    for i in range(1,face.size()-1):
     # Export OBJ is CCW. Godot expects clockwise front faces.
     indices.append(face[0]);indices.append(face[i+1]);indices.append(face[i])
 if out_positions.is_empty() or indices.is_empty():return null
 var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=out_positions;arrays[Mesh.ARRAY_NORMAL]=out_normals;arrays[Mesh.ARRAY_TEX_UV]=out_uvs;arrays[Mesh.ARRAY_INDEX]=indices
 var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 mesh_cache[path]=result
 return result

static func clear_caches()->void:
 json_cache.clear();mesh_cache.clear()

static func source_quad()->ArrayMesh:
 if mesh_cache.has("@native_quad"):return mesh_cache["@native_quad"]
 var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-0.5,-0.5,0),Vector3(-0.5,0.5,0),Vector3(0.5,0.5,0),Vector3(0.5,-0.5,0)])
 arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK])
 arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)])
 arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 mesh_cache["@native_quad"]=mesh
 return mesh
