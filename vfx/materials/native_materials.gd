extends RefCounted
## Source-derived Unity DSFX material adapter for a deterministic native VFX player.
## No shared ShaderMaterial instances: particle uniforms are always independent.
## Shader/texture resources are cached. Unsupported families return null explicitly.

const CharacterMaterials = preload("res://scripts/native_material_adapter.gd")
const ShaderCatalog = preload('native_shader_catalog.gd')
const ShaderPreloads = preload('shader_preloads.gd')
static var _texture_cache: Dictionary = {}
static var _json_cache: Dictionary = {}
static var _shader_cache: Dictionary = {}
static var _default_textures: Dictionary = {}

static func create(material_descriptor: Dictionary, resource_root: String, billboard: bool = false) -> ShaderMaterial:
	if _native_weapon(material_descriptor):
		return null if billboard else _weapon_particle(material_descriptor,resource_root)
	var report: Dictionary = diagnostics(material_descriptor, resource_root)
	if not report.supported:
		return null
	var family: String = _family(material_descriptor)
	var info: Dictionary = ShaderCatalog.CATALOG[family]
	var floats: Dictionary = material_descriptor.get('floats', {})
	var textures: Dictionary = material_descriptor.get('textures', {})
	var shader: Shader = ShaderPreloads.SHADERS[family]
	var code: String = shader.code
	var cull: int = int(_state_value(info, floats, 'culling', 2.0))
	var z_write: bool = _state_value(info, floats, 'zWrite', 0.0) != 0.0
	var z_test: int = int(_state_value(info, floats, 'zTest', 4.0))
	var modes: String = 'unshaded, ' + info.blend_mode
	modes += ', depth_draw_always' if z_write else ', depth_draw_never'
	modes += ', cull_front' if cull == 1 else ', cull_back' if cull == 2 else ', cull_disabled'
	if z_test == 8 or z_test == 0:
		modes += ', depth_test_disabled'
	var first: int = code.find('render_mode ')
	var last: int = code.find(';', first)
	code = code.substr(0, first) + 'render_mode ' + modes + code.substr(last)
	# Use the texture's own filter and wrap flags, not a universal clamp sampler.
	for texture_name: String in info.textures:
		var texture_descriptor: Dictionary = textures.get(texture_name, {})
		var resource: Dictionary = _dictionary(texture_descriptor.get('resource'))
		var tree: Dictionary = _resource_json(resource, resource_root)
		var settings: Dictionary = tree.get('m_TextureSettings', {})
		var filter_mode: int = int(settings.get('m_FilterMode', 1))
		var filter_hint: String = 'filter_nearest' if filter_mode == 0 else 'filter_linear'
		var wrap_u: int = int(settings.get('m_WrapU', 0))
		var wrap_v: int = int(settings.get('m_WrapV', 0))
		var wrap_hint: String = 'repeat_enable' if wrap_u == 0 and wrap_v == 0 else 'repeat_disable'
		var old_line: String = 'uniform sampler2D ' + texture_name + ' : filter_linear, repeat_enable;'
		# Unity TextureColorSpace (not project ColorSpace): Linear=0, sRGB=1.
		var color_hint: String = 'source_color, ' if int(tree.get('m_ColorSpace', 0)) == 1 and str(material_descriptor.get('texture_color_space_mode', 'source')) != 'raw' else ''
		var new_line: String = 'uniform sampler2D ' + texture_name + ' : ' + color_hint + filter_hint + ', ' + wrap_hint + ';'
		code = code.replace(old_line, new_line)
	var key: int = code.hash()
	if not _shader_cache.has(key):
		var configured := Shader.new()
		configured.code = code
		_shader_cache[key] = configured
	var result := ShaderMaterial.new()
	result.shader = _shader_cache[key]
	result.resource_name = str(material_descriptor.get('source', {}).get('name', family))
	result.set_meta('native_diagnostics', report)
	result.set_meta('native_source_descriptor', material_descriptor)
	result.set_shader_parameter('billboard', billboard)
	result.set_shader_parameter('particle_color', Color.WHITE)
	result.set_shader_parameter('custom0', Vector4.ZERO)
	result.set_shader_parameter('custom1', Vector4.ZERO)
	result.set_shader_parameter('effect_time', 0.0)
	result.set_shader_parameter('uv_sheet', Vector4(1.0, 1.0, 0.0, 0.0))
	result.set_shader_parameter('roll', 0.0)
	for property_name: String in info.defaults:
		var value: Variant = info.defaults[property_name]
		if value is Array:
			result.set_shader_parameter(property_name, Vector4(value[0], value[1], value[2], value[3]))
		else:
			result.set_shader_parameter(property_name, float(value))
	for property_name: String in floats:
		if info.defaults.has(property_name):
			result.set_shader_parameter(property_name, float(floats[property_name]))
	for property_name: String in material_descriptor.get('ints', {}):
		if info.defaults.has(property_name):
			result.set_shader_parameter(property_name, float(material_descriptor.ints[property_name]))
	for property_name: String in material_descriptor.get('colors', {}):
		if info.defaults.has(property_name):
			var color: Dictionary = material_descriptor.colors[property_name]
			# Vector4 avoids implicit color UI conversions and keeps source HDR/negative values.
			result.set_shader_parameter(property_name, Vector4(color.get('r', 0.0), color.get('g', 0.0), color.get('b', 0.0), color.get('a', 0.0)))
	for texture_name: String in info.textures:
		var texture_descriptor: Dictionary = textures.get(texture_name, {})
		var resource: Dictionary = _dictionary(texture_descriptor.get('resource'))
		var tex: Texture2D = _load_texture(resource, resource_root)
		if tex == null:
			tex = _default_texture(str(info.texture_defaults.get(texture_name, 'white')))
		result.set_shader_parameter(texture_name, tex)
		var scale: Dictionary = texture_descriptor.get('scale', {})
		var offset: Dictionary = texture_descriptor.get('offset', {})
		result.set_shader_parameter(texture_name + '_ST', Vector4(scale.get('x', 1.0), scale.get('y', 1.0), offset.get('x', 0.0), offset.get('y', 0.0)))
	var queue: int = int(material_descriptor.get('renderQueue', -1))
	if queue >= 0:
		result.render_priority = clampi(queue - 3000, -128, 127)
	return result

static func diagnostics(material_descriptor: Dictionary, resource_root: String = '') -> Dictionary:
	var family: String = _family(material_descriptor)
	var report: Dictionary = {
		'supported': ShaderCatalog.CATALOG.has(family),
		'family': family,
		'source_material': material_descriptor.get('source', {}).get('name', ''),
		'fidelity': 'source fragment arithmetic and material constants; Unity/Godot HDR and color-space pipeline not calibrated',
		'warnings': [],
		'missing_textures': [],
		'texture_color_space_mode': str(material_descriptor.get('texture_color_space_mode', 'source')),
	}
	if _native_weapon(material_descriptor):
		report.supported=true;report.custom_streams=[];report.blend=[1.0,0.0]
		report.source_tree=material_descriptor.get("shader",{}).get("tree","")
		report.warnings.append("Opaque native weapon-mesh pass; particle vertex color is unused by the source shader. Scene lighting remains the existing preview adaptation.")
		for slot in ["_MainTex","_SourceTex"]:
			var resource:Dictionary=_dictionary(material_descriptor.get("textures",{}).get(slot,{}).get("resource"))
			if not resource.is_empty() and resource_root!="" and not _texture_path_exists(_absolute_path(resource_root,str(resource.get("png","")))):report.missing_textures.append(slot)
		return report
	if not report.supported:
		report.warnings.append('Unsupported shader family: no guessed fallback material was created')
		return report
	var info: Dictionary = ShaderCatalog.CATALOG[family]
	report.source_tree = info.source_tree
	report.source_sha256 = info.source_sha256
	report.custom_streams = info.custom_streams
	report.blend = info.blend
	report.warnings.append('Source texture color-space flags select sRGB/data sampling; material HDR vectors remain raw. Unity project working space, render target, bloom and tone mapping remain unverified. Set texture_color_space_mode=raw for explicit gamma-project comparison')
	var floats: Dictionary = material_descriptor.get('floats', {})
	var z_test: int = int(_state_value(info, floats, 'zTest', 4.0))
	if z_test not in [0, 4, 8]:
		report.warnings.append('Unity ZTest %d is not directly available in Godot spatial shader render modes; engine default comparison is used' % z_test)
	for property_name: String in ['_ZOffsetFactor', '_ZOffsetUnits']:
		if float(floats.get(property_name, 0.0)) != 0.0:
			report.warnings.append(property_name + ' polygon depth bias is unsupported')
	var queue: int = int(material_descriptor.get('renderQueue', -1))
	if queue >= 0 and (queue < 2872 or queue > 3127):
		report.warnings.append('Render queue is mapped to Godot priority with [-128,127] clamping')
	if resource_root != '':
		for texture_name: String in info.textures:
			var resource: Dictionary = _dictionary(material_descriptor.get('textures', {}).get(texture_name, {}).get('resource'))
			if resource.is_empty():
				continue # An unassigned source texture uses the shader's declared default.
			var png: String = str(resource.get('png', ''))
			if png == '' or not _texture_path_exists(_absolute_path(resource_root, png)):
				report.missing_textures.append(texture_name + ': ' + png)
			var tree: Dictionary = _resource_json(resource, resource_root)
			var settings: Dictionary = tree.get('m_TextureSettings', {})
			var u: int = int(settings.get('m_WrapU', 0))
			var v: int = int(settings.get('m_WrapV', 0))
			if u != v or u not in [0, 1]:
				report.warnings.append(texture_name + ': asymmetric/mirror wrap is not natively expressible by the sampler; clamped')
			if int(tree.get('m_MipCount', 1)) > 1:
				report.warnings.append(texture_name + ': source mip chain was not exported; level-zero PNG is used')
	if not report.missing_textures.is_empty():
		report.warnings.append('Missing assigned textures use the source shader default; inspect missing_textures')
	return report

static func _family(descriptor: Dictionary) -> String:
	return str(_dictionary(descriptor.get('shader')).get('name', ''))

static func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _state_value(info: Dictionary, floats: Dictionary, key: String, fallback: float) -> float:
	var state: Dictionary = info.get('state', {}).get(key, {})
	var property_name: String = str(state.get('name', ''))
	if floats.has(property_name):
		return float(floats[property_name])
	if property_name != '' and property_name != '<noninit>':
		return float(info.get('defaults', {}).get(property_name, fallback))
	return float(state.get('val', fallback))

static func _absolute_path(root: String, relative_path: String) -> String:
	return relative_path if relative_path.is_absolute_path() or relative_path.begins_with('res://') else root.path_join(relative_path)

static func _resource_json(resource: Dictionary, root: String) -> Dictionary:
	var relative_path: String = str(resource.get('tree', ''))
	if relative_path == '':
		return {}
	var path: String = _absolute_path(root, relative_path)
	if not _json_cache.has(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_json_cache[path] = _dictionary(parsed)
	return _json_cache[path]

static func _load_texture(resource: Dictionary, root: String) -> Texture2D:
	var relative_path: String = str(resource.get('png', ''))
	if relative_path == '':
		return null
	var path: String = _absolute_path(root, relative_path)
	if not _texture_cache.has(path):
		var image: Image = null
		if FileAccess.file_exists(path):
			# Read exact source PNG bytes in both filesystem and PCK. This avoids
			# the misleading raw-resource export warning from Image.load_from_file.
			if path.get_extension().to_lower() == "png":
				image = Image.new()
				if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
					image = null
			else:
				image = Image.load_from_file(path)
		# Exported packs can retain only an imported Texture2D plus its remap.
		# ResourceLoader understands that remap even when the raw PNG is absent.
		if (image == null or image.is_empty()) and path.begins_with('res://') and ResourceLoader.exists(path):
			var imported: Texture2D = ResourceLoader.load(path) as Texture2D
			if imported != null:
				var imported_image: Image = imported.get_image()
				if imported_image != null:
					image = imported_image.duplicate() as Image
		if image == null or image.is_empty():
			return null
		if image.is_compressed() and image.decompress() != OK:
			return null
		# UnityPy exports PNGs with flip=True (get_image_from_texture2d / parse_image_data).
		# Restore source texture row order so original Unity UV, ST, scroll and sheet math
		# remain untouched. Caller supplies Unity-style bottom-left UVs for quads/meshes.
		image.flip_y()
		_texture_cache[path] = ImageTexture.create_from_image(image)
	return _texture_cache[path]

static func _texture_path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or (path.begins_with('res://') and ResourceLoader.exists(path))

static func _default_texture(default_name: String) -> Texture2D:
	if not _default_textures.has(default_name):
		var color := Color.WHITE
		if default_name == 'black':
			color = Color(0.0, 0.0, 0.0, 0.0)
		elif default_name in ['gray', 'grey']:
			color = Color(0.5, 0.5, 0.5, 0.5)
		elif default_name == 'bump':
			color = Color(0.5, 0.5, 1.0, 0.5)
		elif default_name == 'red':
			color = Color.RED
		var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(color)
		_default_textures[default_name] = ImageTexture.create_from_image(image)
	return _default_textures[default_name]

static func _native_weapon(descriptor:Dictionary)->bool:
	return _family(descriptor)=="MX/C-Weapon" and str(descriptor.get("shader",{}).get("pathId",""))==CharacterMaterials.WEAPON_SHADER_ID

static func _weapon_particle(descriptor:Dictionary,resource_root:String)->ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=load("res://shaders/native_weapon.gdshader")
	var textures:Dictionary=descriptor.get("textures",{})
	for pair in [["_MainTex","main_texture"],["_SourceTex","source_texture"]]:
		var texture:Texture2D=_load_texture(_dictionary(textures.get(pair[0],{}).get("resource")),resource_root)
		if texture==null:texture=_default_texture("white")
		material.set_shader_parameter(pair[1],texture)
	var floats:Dictionary=descriptor.get("floats",{})
	for key in CharacterMaterials.WEAPON_FLOAT_PROPERTIES:
		if floats.has(key):material.set_shader_parameter(CharacterMaterials.WEAPON_FLOAT_PROPERTIES[key],float(floats[key]))
	CharacterMaterials._set_vector3_properties(material,descriptor.get("colors",{}),CharacterMaterials.WEAPON_VECTOR3_PROPERTIES)
	var keywords:Variant=descriptor.get("keywords",[])
	material.set_shader_parameter("glow_enabled",keywords is Array and "_GLOW_0" in keywords)
	material.resource_name=str(descriptor.get("source",{}).get("name","native weapon particle"))
	material.set_meta("native_diagnostics",diagnostics(descriptor,resource_root))
	material.set_meta("native_source_descriptor",descriptor)
	return material
