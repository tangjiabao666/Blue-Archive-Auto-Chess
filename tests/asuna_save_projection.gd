extends RefCounted
## Reverse only the approved roster addition; never erase a changed Asuna row.
const ASUNA={"id":"asuna","name":"明日奈","cost":1,"ex_cooldown":15.0}
static func legacy_catalog(current:Array)->Array:
	if current.size()!=14 or current.back()!=ASUNA:return []
	return current.slice(0,13).duplicate(true)
