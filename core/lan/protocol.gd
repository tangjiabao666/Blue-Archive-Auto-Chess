extends RefCounted
const VERSION:=1
const BUILD_ID:='blue-a-lan-20261005-v1-rules3'
const CONTROL_LIMIT:=4096
const VIEW_LIMIT:=65536
const TYPES=['hello','welcome','room_state','ready','begin','leave','ping','pong','error','intent','ack','view','loaded','next','ended']
static func encode(message:Dictionary)->PackedByteArray:
 if not _valid(message):return PackedByteArray()
 var bytes:PackedByteArray=JSON.stringify(message).to_utf8_buffer()
 return bytes if bytes.size()<=(VIEW_LIMIT if message.type=='view' else CONTROL_LIMIT) else PackedByteArray()
static func decode(bytes:PackedByteArray)->Dictionary:
 if bytes.is_empty() or bytes.size()>VIEW_LIMIT:return {'ok':false,'error':'packet_size'}
 var value:Variant=JSON.parse_string(bytes.get_string_from_utf8())
 if not value is Dictionary or not _valid(value):return {'ok':false,'error':'invalid_message'}
 if bytes.size()>(VIEW_LIMIT if value.type=='view' else CONTROL_LIMIT):return {'ok':false,'error':'packet_size'}
 for field in ['protocol','epoch','seq']:value[field]=int(value[field])
 return {'ok':true,'message':value}
static func _valid(value:Dictionary)->bool:
 if value.size()!=5:return false
 for key in ['protocol','type','epoch','seq','payload']:
  if not value.has(key):return false
 return whole(value.protocol) and int(value.protocol)==VERSION and value.type is String and value.type in TYPES and whole(value.epoch) and whole(value.seq) and value.payload is Dictionary and safe(value.payload)
static func whole(value:Variant)->bool:
 return (value is int or value is float) and is_finite(float(value)) and value>=0 and value<=9007199254740991 and value==floor(value)
static func safe(value:Variant,depth:int=0)->bool:
 if depth>12:return false
 if value==null:return true
 if value is bool:return true
 if value is int or value is float:return is_finite(float(value)) and absf(float(value))<=9007199254740991.0
 if value is String:return value.length()<=VIEW_LIMIT
 if value is Array:
  if value.size()>512:return false
  for item in value:
   if not safe(item,depth+1):return false
  return true
 if value is Dictionary:
  if value.size()>128:return false
  for key in value:
   if not (key is String or key is StringName) or str(key).length()>64 or not safe(value[key],depth+1):return false
  return true
 return false
static func is_lan_address(ip:String)->bool:
 var parts:PackedStringArray=ip.split('.')
 if parts.size()!=4:return false
 var n:Array=[]
 for part in parts:
  if part.is_empty() or not part.is_valid_int() or str(int(part))!=part or int(part)<0 or int(part)>255:return false
  n.append(int(part))
 return n[0]==10 or n[0]==127 or (n[0]==192 and n[1]==168) or (n[0]==172 and n[1]>=16 and n[1]<=31)
