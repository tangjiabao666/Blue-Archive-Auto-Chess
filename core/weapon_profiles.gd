extends RefCounted
# Prototype arena units, not real-world firearm ranges or official BA numbers.
const RANGES := {"SG":1.8,"HG":2.4,"SMG":2.8,"AR":3.8,"MG":4.0,"SR":5.2,"RG":5.5,"GL":3.6,"RL":4.2}
static func range_for(kind:String)->float:
	return float(RANGES.get(kind,-1.0))
