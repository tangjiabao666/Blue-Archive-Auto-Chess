extends RefCounted
const Protocol=preload('res://core/lan/protocol.gd')
static func pack(value:Variant)->Variant:
 if value is Vector2:return {'$v2':[value.x,value.y]}
 if value is Rect2:return {'$rect':[value.position.x,value.position.y,value.size.x,value.size.y]}
 if value is Array:
  var out:Array=[]
  for item in value:out.append(pack(item))
  return out
 if value is Dictionary:
  var out:Dictionary={}
  for key in value:out['$i'+str(key) if key is int else str(key)]=pack(value[key])
  return out
 return value
static func unpack(value:Variant)->Variant:
 if value is Array:
  var out:Array=[]
  for item in value:out.append(unpack(item))
  return out
 if value is Dictionary:
  if value.size()==1 and value.get('$v2') is Array and value['$v2'].size()==2:
   var a:Array=value['$v2']
   if _number(a[0]) and _number(a[1]):return Vector2(a[0],a[1])
  if value.size()==1 and value.get('$rect') is Array and value['$rect'].size()==4:
   var a:Array=value['$rect']
   if a.all(func(n):return _number(n)):return Rect2(a[0],a[1],a[2],a[3])
  var out:Dictionary={}
  for key in value:
   var decoded:Variant=int(key.substr(2)) if key.begins_with('$i') and key.substr(2).is_valid_int() else key
   out[decoded]=unpack(value[key])
  return out
 if value is float and value==floor(value) and absf(value)<=9007199254740991:return int(value)
 return value
static func _number(value:Variant)->bool:return (value is int or value is float) and is_finite(float(value))
