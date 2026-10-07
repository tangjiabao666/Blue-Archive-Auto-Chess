extends RefCounted
## Frozen pre-interning parser for differential tests only.
static func read_original(path:String)->Dictionary:
 var raw:=FileAccess.get_file_as_string(path)
 var rx:=RegEx.new();rx.compile("(?<=[:,\\[\\s])(-?Infinity|NaN)(?=[,}\\]\\s])")
 var tokens:Dictionary={}
 for token in rx.search_all(raw):tokens[token.get_string()]=true
 for value in tokens:raw=raw.replace(value,"-1e30" if value=="-Infinity" else "1e30" if value=="Infinity" else "0.0")
 var parsed=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func deeply_read_only(value:Variant)->bool:
 if value is Dictionary:
  if not value.is_read_only():return false
  for item in value.values():
   if not deeply_read_only(item):return false
 elif value is Array:
  if not value.is_read_only():return false
  for item in value:
   if not deeply_read_only(item):return false
 return true
