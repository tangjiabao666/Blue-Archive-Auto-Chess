extends RefCounted
## Pure bounded screen-space layout. No nodes, time, randomness or simulation.
## Input IDs must be unique. Oversized axes retain size and pin to bounds origin.
## Optional item.preferred is a previous placement translated by anchor motion.
const MAX_OFFSET:=200.0
const GAP:=4.0
func arrange(items:Array,bounds:Rect2,priority_id:int=-1)->Dictionary:
	var ordered:Array=items.duplicate()
	ordered.sort_custom(func(a:Dictionary,b:Dictionary):
		if int(a.id)==priority_id:return int(b.id)!=priority_id
		if int(b.id)==priority_id:return false
		return int(a.id)<int(b.id)
	)
	var area:Rect2=bounds.abs()
	var placed:Dictionary={}
	var occupied:Array[Rect2]=[]
	var offsets_by_size:Dictionary={}
	for item in ordered:
		var source:Rect2=item.rect
		var anchor:=Rect2(_clamp_position(source.position,source.size,area),source.size)
		var best:Rect2=anchor
		var best_overlap:float=_overlap_area(anchor,occupied)
		var best_distance:=0.0
		if best_overlap>0.0:
			var preferred:Variant=item.get("preferred")
			if _can_use_preferred(preferred,anchor,area,occupied):
				best=preferred
			else:
				if not offsets_by_size.has(source.size):offsets_by_size[source.size]=_candidate_offsets(source.size)
				var visited:Dictionary={anchor.position:true}
				for offset in offsets_by_size[source.size]:
					var candidate:=Rect2(_clamp_position(anchor.position+offset,source.size,area),source.size)
					if visited.has(candidate.position):continue
					visited[candidate.position]=true
					var overlap:float=_overlap_area(candidate,occupied,best_overlap)
					var distance:float=candidate.position.distance_squared_to(anchor.position)
					if overlap<best_overlap or (overlap==best_overlap and distance<best_distance):
						best=candidate;best_overlap=overlap;best_distance=distance
					if best_overlap==0.0:break
		placed[int(item.id)]=best;occupied.append(best)
	return placed
func _can_use_preferred(preferred:Variant,anchor:Rect2,bounds:Rect2,occupied:Array[Rect2])->bool:
	if typeof(preferred)!=TYPE_RECT2:return false
	var rect:Rect2=preferred
	return rect.size==anchor.size and bounds.encloses(rect) and rect.position.distance_squared_to(anchor.position)<=MAX_OFFSET*MAX_OFFSET and _overlap_area(rect,occupied)==0.0
func _clamp_position(position:Vector2,size:Vector2,bounds:Rect2)->Vector2:
	return Vector2(
		clampf(position.x,bounds.position.x,maxf(bounds.position.x,bounds.end.x-size.x)),
		clampf(position.y,bounds.position.y,maxf(bounds.position.y,bounds.end.y-size.y))
	)
func _candidate_offsets(size:Vector2)->Array[Vector2]:
	# Quarter-tile sampling finds nearby gaps without an unbounded pixel search.
	# For the production 92x70 block there are fewer than 300 candidates.
	var step:=Vector2(maxf(4.0,(size.x+GAP)*0.25),maxf(4.0,(size.y+GAP)*0.25))
	var columns:int=int(floor(MAX_OFFSET/step.x));var rows:int=int(floor(MAX_OFFSET/step.y))
	var offsets:Array[Vector2]=[]
	for y in range(-rows,rows+1):
		for x in range(-columns,columns+1):
			var offset:=Vector2(x*step.x,y*step.y)
			if offset!=Vector2.ZERO and offset.length_squared()<=MAX_OFFSET*MAX_OFFSET:offsets.append(offset)
	offsets.sort_custom(func(a:Vector2,b:Vector2):
		var a_length:float=a.length_squared();var b_length:float=b.length_squared()
		if a_length!=b_length:return a_length<b_length
		return a.x<b.x if a.y==b.y else a.y<b.y
	)
	return offsets
func _overlap_area(rect:Rect2,occupied:Array[Rect2],stop_after:float=INF)->float:
	var total:=0.0
	for other in occupied:
		if rect.intersects(other):total+=rect.intersection(other).get_area()
		if total>stop_after:return total
	return total
