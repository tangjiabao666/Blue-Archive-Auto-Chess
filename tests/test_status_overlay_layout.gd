extends SceneTree
const SIZE:=Vector2(92,70)
const BOUNDS:=Rect2(16,110,984,535)
class CountingLayout extends "res://core/status_overlay_layout.gd":
	var searches:=0
	func _candidate_offsets(size:Vector2)->Array[Vector2]:
		searches+=1
		return super._candidate_offsets(size)
var checks:=0
var failures:=0
func ck(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func _item(id:int,position:Vector2)->Dictionary:
	return {"id":id,"rect":Rect2(position,SIZE)}
func _no_overlap(placed:Dictionary)->bool:
	var ids:Array=placed.keys()
	for i in ids.size():
		for j in range(i+1,ids.size()):
			if placed[ids[i]].intersects(placed[ids[j]]):return false
	return true
func _check_output(items:Array,placed:Dictionary,bounds:Rect2,label:String)->void:
	ck(placed.size()==items.size(),label+" retains every unit")
	for item in items:
		ck(placed.has(item.id),label+" retains ID "+str(item.id))
		if not placed.has(item.id):continue
		var rect:Rect2=placed[item.id]
		ck(rect.size==item.rect.size,label+" preserves complete overlay size")
		ck(bounds.encloses(rect),label+" stays inside board")
		var anchor:=Vector2(clampf(item.rect.position.x,bounds.position.x,bounds.end.x-item.rect.size.x),clampf(item.rect.position.y,bounds.position.y,bounds.end.y-item.rect.size.y))
		ck(rect.position.distance_to(anchor)<=200.001,label+" remains within bounded anchor distance")
func run():
	# An absent layout engine must fail before any implementation is introduced.
	ck(ResourceLoader.exists("res://core/status_overlay_layout.gd"),"pure status overlay layout exists")
	if failures:print("STATUS OVERLAY LAYOUT ",checks," checks; ",failures," failures");quit(1);return
	var layout=load("res://core/status_overlay_layout.gd").new()
	var normal:Array=[_item(8,Vector2(200,200)),_item(2,Vector2(400,200)),_item(5,Vector2(400,400))]
	var before:Array=normal.duplicate(true)
	var placed:Dictionary=layout.arrange(normal,BOUNDS)
	for item in normal:ck(placed[item.id]==item.rect,"non-overlapping original position is unchanged")
	ck(normal==before,"normal inputs are unchanged")
	ck(layout.arrange([],BOUNDS).is_empty(),"empty input returns an empty map")
	ck(layout.arrange(normal,BOUNDS,999)==placed,"absent priority ID changes nothing")
	var dense:Array=[]
	for i in 12:dense.append(_item(i,Vector2(430+(i%4)*12,250+(i/4)*8)))
	before=dense.duplicate(true)
	placed=layout.arrange(dense,BOUNDS)
	_check_output(dense,placed,BOUNDS,"dense center")
	ck(_no_overlap(placed),"all twelve dense-center overlays avoid collisions")
	ck(placed[0]==dense[0].rect,"lowest ID keeps its preferred rectangle")
	ck(dense==before,"dense input dictionaries and rectangles are unchanged")
	var reversed:Array=dense.duplicate(true);reversed.reverse()
	ck(layout.arrange(reversed,BOUNDS)==placed,"input order never changes placement")
	ck(layout.arrange(dense,BOUNDS)==placed,"repeated calls are deterministic")
	var priority:Dictionary=layout.arrange(dense,BOUNDS,11)
	ck(priority[11]==dense[11].rect,"priority unit keeps its original rectangle")
	ck(_no_overlap(priority),"priority ordering still resolves all twelve dense-center overlays")
	ck(layout.arrange(reversed,BOUNDS,11)==priority,"priority output is also independent of input order")
	var coincident:Array=[]
	for i in 12:coincident.append(_item(i,Vector2(430,250)))
	var coincident_result:Dictionary=layout.arrange(coincident,BOUNDS)
	_check_output(coincident,coincident_result,BOUNDS,"coincident center")
	ck(_no_overlap(coincident_result),"twelve identical anchors remain separable")
	var integrated_bounds:=Rect2(8,112,984,530)
	var integrated:Array=[]
	for i in 12:integrated.append({"id":i,"rect":Rect2(430+(i%4)*12,250+(i/4)*8,92,75)})
	var integrated_result:Dictionary=layout.arrange(integrated,integrated_bounds,11)
	_check_output(integrated,integrated_result,integrated_bounds,"integrated 92 by 75 center")
	ck(_no_overlap(integrated_result),"root's complete 92 by 75 rectangle stays collision-free")
	for priority_id in 12:
		integrated_result=layout.arrange(integrated,integrated_bounds,priority_id)
		ck(integrated_result[priority_id]==integrated[priority_id].rect,"each possible priority keeps its original rectangle")
		ck(_no_overlap(integrated_result),"each possible priority resolves the integrated dense fixture")
	var edges:Array=[_item(1,Vector2(-30,60)),_item(2,Vector2(30,80)),_item(3,Vector2(970,600)),_item(4,Vector2(995,550))]
	before=edges.duplicate(true)
	var edge_result:Dictionary=layout.arrange(edges,BOUNDS)
	_check_output(edges,edge_result,BOUNDS,"board edges")
	ck(_no_overlap(edge_result),"clamping adjacent edge overlays does not leave avoidable collisions")
	ck(edges==before,"edge inputs remain unchanged")
	var small_bounds:=Rect2(10,20,120,90)
	var impossible:Array=[_item(0,small_bounds.position),_item(1,small_bounds.position)]
	var fallback:Dictionary=layout.arrange(impossible,small_bounds)
	ck(fallback.size()==2,"impossible layout never hides an overlay")
	ck(fallback[0]==impossible[0].rect,"first impossible item still prefers its original position")
	ck(fallback[1].position==small_bounds.end-SIZE,"impossible overlap is minimized at the opposite feasible corner")
	ck(fallback[1].intersection(fallback[0]).get_area()==3200.0,"fallback minimizes overlap area rather than hiding information")
	ck(layout.arrange(impossible,small_bounds)==fallback,"impossible result is deterministic")
	var tiny_bounds:=Rect2(10,20,40,30)
	fallback=layout.arrange(impossible,tiny_bounds)
	for id in fallback:ck(fallback[id]==Rect2(tiny_bounds.position,SIZE),"oversized rectangle preserves size and pins to bounds origin")
	var zero_bounds:=Rect2(10,20,0,0)
	fallback=layout.arrange(impossible,zero_bounds)
	ck(fallback.size()==2 and fallback[0]==Rect2(zero_bounds.position,SIZE),"zero bounds have explicit size-preserving fallback")
	var pair:Array=[_item(0,Vector2(430,250)),_item(1,Vector2(430,250))]
	var without_preferred:Dictionary=layout.arrange(pair,BOUNDS)
	pair[0].preferred=Rect2(230,250,92,70)
	pair[1].preferred=Rect2(550,330,92,70)
	before=pair.duplicate(true)
	var preferred_result:Dictionary=layout.arrange(pair,BOUNDS)
	ck(preferred_result[0]==pair[0].rect,"clear original anchor wins over preferred placement")
	ck(preferred_result[1]==pair[1].preferred,"valid preferred placement skips the finite search")
	ck(pair==before,"preferred input is not changed")
	for invalid in [null,"not a rectangle",Rect2(550,330,93,70),Rect2(-10,250,92,70),Rect2(630.1,250,92,70),Rect2(430,250,92,70)]:
		pair[1].preferred=invalid
		ck(layout.arrange(pair,BOUNDS)==without_preferred,"invalid, resized, outside, too-far or colliding preferred position is ignored")
	pair[1].preferred=Rect2(630,250,92,70)
	ck(layout.arrange(pair,BOUNDS)[1]==pair[1].preferred,"preferred position exactly at the radial limit is accepted")
	var previous:Dictionary=layout.arrange(integrated,integrated_bounds,11)
	var moved:Array=integrated.duplicate(true)
	var translated:Dictionary={}
	var delta:=Vector2(1.5,1.25)
	for item in moved:
		item.rect=Rect2(item.rect.position+delta,item.rect.size)
		item.preferred=Rect2(previous[item.id].position+delta,previous[item.id].size)
		translated[item.id]=item.preferred
	before=moved.duplicate(true)
	var counting=CountingLayout.new()
	var moved_result:Dictionary=counting.arrange(moved,integrated_bounds,11)
	ck(moved_result==translated,"moving a resolved cluster preserves identical relative geometry")
	ck(counting.searches==0,"warm translated cluster never generates search candidates")
	ck(moved==before,"moving preferred inputs remain unchanged")
	moved.reverse()
	ck(layout.arrange(moved,integrated_bounds,11)==moved_result,"preferred placement stays independent of input order")
	print("STATUS OVERLAY LAYOUT ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
