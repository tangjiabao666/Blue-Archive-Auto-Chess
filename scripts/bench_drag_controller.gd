extends RefCounted
## Input-only transaction arbiter; Session remains authoritative for deployment.
const DRAG_THRESHOLD:=6.0
var unit_id:=""
var pointer:=Vector2.ZERO
var _origin:=Vector2.ZERO
var _dragging:=false
var _generation:=-1
var _deploy:Callable
var _preview:Callable
var _current_generation:Callable
func configure(deploy:Callable,preview:Callable,generation:Callable)->void:
 cancel();_deploy=deploy;_preview=preview;_current_generation=generation
func begin(id:String,screen:Vector2)->bool:
 cancel()
 if id.is_empty() or not screen.is_finite() or not _deploy.is_valid() or not _preview.is_valid() or not _current_generation.is_valid():return false
 unit_id=id;pointer=screen;_origin=screen;_generation=int(_current_generation.call());return true
func update(screen:Vector2)->void:
 if not is_pending() or not screen.is_finite():return
 pointer=screen
 if pointer.distance_to(_origin)>=DRAG_THRESHOLD:_dragging=true
func is_pending()->bool:return not unit_id.is_empty()
func is_dragging()->bool:return is_pending() and _dragging
func preview(point:Variant)->Dictionary:
 if not is_dragging():return {'ok':false,'error':'drag_not_active'}
 if not _current_generation.is_valid() or int(_current_generation.call())!=_generation:return {'ok':false,'error':'stale_deployment'}
 if not point is Vector2 or not point.is_finite():return {'ok':false,'error':'invalid_deployment_point'}
 if not _preview.is_valid():return {'ok':false,'error':'deployment_unavailable'}
 return _preview.call(unit_id,point)
func drop(point:Variant)->Dictionary:
 var checked:Dictionary=preview(point);var id:String=unit_id
 cancel()
 if not checked.ok:return checked
 if not _deploy.is_valid():return {'ok':false,'error':'deployment_unavailable'}
 return _deploy.call(id,point)
func cancel()->void:
 unit_id='';pointer=Vector2.ZERO;_origin=Vector2.ZERO;_dragging=false;_generation=-1
