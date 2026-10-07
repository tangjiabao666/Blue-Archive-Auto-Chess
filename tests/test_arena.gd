extends SceneTree
const Arena=preload("res://core/arena_sim.gd")
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func unit(id:int,team:int,p:Vector2)->Dictionary:
	return {"id":id,"team":team,"cell":p,"hp":180,"damage":16,"range":2.0,"skill":["single","area","shield"][id%3]}
func _initialize()->void:
	var s=Arena.new()
	var roster=[unit(0,0,Vector2(-2.0,2.0)),unit(1,0,Vector2(0,1)),unit(2,0,Vector2(2,2)),unit(3,1,Vector2(-2,-2)),unit(4,1,Vector2(0,-1)),unit(5,1,Vector2(2,-2))]
	ck(s.configure(roster)=="","continuous roster configures")
	if s.units.is_empty():quit(1);return
	var free=Vector2(-1.234,2.789)
	ck(s.place(0,free) and s.units[0].cell==free,"free position preserved without snapping")
	ck(not s.place(0,Vector2(0,1)),"reject character overlap")
	ck(not s.place(0,Vector2(0,-1)),"reject opponent territory")
	ck(not s.place(0,Vector2(5,1)),"reject out of arena")
	ck(not s.place(0,Vector2(NAN,1)),"reject nonfinite position")
	s.start()
	var previous={}
	for u in s.units:previous[u.id]=u.cell
	for i in range(1200):
		s.step()
		for u in s.units:
			ck(u.cell.is_finite(),"finite coordinates")
			ck(u.cell.distance_to(previous[u.id])<=0.126,"movement bounded by continuous speed")
			previous[u.id]=u.cell
			if u.hp>0:
				for v in s.units:
					if u.id<v.id and v.hp>0:ck(u.cell.distance_to(v.cell)>=0.6999,"collision radius respected")
		if s.phase=="finished":break
	ck(s.phase=="finished","continuous battle terminates")
	s.reset();ck(s.units[0].cell==free and s.phase=="prepare","reset preserves free formation")
	print("ARENA FAILURES=",fails);quit(1 if fails else 0)
