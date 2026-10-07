extends RefCounted
## Ordered left/right limits at a discontinuity share a timestamp. The first
## sample at t is the endpoint approached from below; the last is used at/after t.
## Callers pin event-origin anchors separately to preserve same-tick causality.
static func record(samples:Array,sample:Dictionary,seconds:float,cap:int)->void:
 var at:float=float(sample.time)
 if not samples.is_empty():
  if at<float(samples[-1].time)-0.0000001:return # Rewind needs reset/replay.
  if samples[-1]==sample:return # Frozen updates do not grow the history.
 samples.append(sample)
 while samples.size()>maxi(2,cap) or (samples.size()>2 and at-float(samples[1].time)>seconds):samples.pop_front()
