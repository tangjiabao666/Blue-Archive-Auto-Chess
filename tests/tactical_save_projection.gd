extends RefCounted
## Reverse only the declared Save10 legacy-mode envelope; reject changed modes.
static func legacy_envelope(current:Dictionary)->Dictionary:
 if current.get('version')!=10 or current.get('combat_mode')!='legacy':return {}
 if current.size()!=11 or current.get("match_format")!="survival" or current.get("arena_version")!=0:return {}
 if current.get("rules_profile")!=0:return {}
 var result:Dictionary=current.duplicate(true)
 result.erase('rules_profile');result.erase('match_format');result.erase('arena_version');result.erase('combat_mode');result.version=5
 return result
