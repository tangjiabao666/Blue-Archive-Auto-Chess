extends RefCounted
## Experimental orientation ONLY, not a Unity stretch-length or motion emulator.
## The caller supplies an absolute-time camera snapshot and current trajectory velocity.
## Source dimensions, position, timing, RNG, materials, and numerics are not changed.
const EPS:=0.000001

static func orient(legacy:Transform3D,world_velocity:Vector3,camera:Dictionary,at:float)->Dictionary:
 var unchanged:Dictionary={"applied":false,"transform":legacy,"reason":""}
 if not is_finite(at) or not legacy.is_finite() or not world_velocity.is_finite():
  unchanged.reason="nonfinite_input";return unchanged
 if not camera.get("transform") is Transform3D or not camera.has("time") or float(camera.time)!=at:
  unchanged.reason="missing_or_stale_camera_snapshot";return unchanged
 var camera_transform:Transform3D=camera.transform
 if not camera_transform.is_finite() or absf(camera_transform.basis.determinant())<EPS:
  unchanged.reason="invalid_camera_transform";return unchanged
 var projection:String=str(camera.get("projection",""))
 if projection not in ["orthographic","perspective"]:
  unchanged.reason="unsupported_camera_projection";return unchanged
 if world_velocity.length_squared()<EPS*EPS:
  unchanged.reason="zero_velocity_orientation_undefined";return unchanged
 var view:Vector3=camera_transform.basis.z.normalized() if projection=="orthographic" else camera_transform.origin-legacy.origin
 if view.length_squared()<EPS*EPS:
  unchanged.reason="camera_at_particle";return unchanged
 view=view.normalized()
 var axis_y:Vector3=world_velocity.normalized()
 var axis_x:Vector3=axis_y.cross(view)
 var degenerate:bool=axis_x.length_squared()<EPS*EPS
 if degenerate:
  # Stateless deterministic limit. No previous-frame orientation or wall clock.
  # Long axis remains on velocity, so its projected length tends to zero.
  axis_x=camera_transform.basis.x-axis_y*camera_transform.basis.x.dot(axis_y)
  if axis_x.length_squared()<EPS*EPS:
   axis_x=camera_transform.basis.y-axis_y*camera_transform.basis.y.dot(axis_y)
 if axis_x.length_squared()<EPS*EPS:
  unchanged.reason="degenerate_camera_basis";return unchanged
 axis_x=axis_x.normalized()
 var axis_z:Vector3=axis_x.cross(axis_y).normalized()
 var dimensions:Vector3=legacy.basis.get_scale().abs()
 var result:=Transform3D(Basis(axis_x,axis_y,axis_z).scaled_local(dimensions),legacy.origin)
 return {"applied":true,"transform":result,"reason":"head_on_deterministic_limit" if degenerate else "orientation_only_existing_trajectory"}
