extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func unit(id:int,team:int,cell:Vector2)->Dictionary:return {'id':id,'team':team,'cell':cell,'hp':100}
func spec(shape:String='line')->Dictionary:
 return {'source':0,'team':0,'ability':'ex','cast_start_tick':0,'shape':shape,'origin':Vector2.ZERO,'direction':Vector2.UP,'centers':[Vector2(0,-2)],'radius':1.25,'width':2.0,'length':10.0,'degrees':60.0,'contact_policy':'area','impacts':[{'due':5,'hit':{'source':0,'effect':'damage','ability':'ex','atk_ratio':1.0,'hit_index':0}}]}
func _initialize()->void:
 var path:='res://core/attack_volumes.gd';ck(FileAccess.file_exists(path),'authoritative attack volumes exist')
 if failures:finish();return
 var v=load(path).new();var s:Dictionary=spec();ck(v.schedule(s)==0,'schedule volume')
 s.width=99;ck(v.snapshot()[0].width==2.0,'schedule detached')
 var units:Array=[unit(0,0,Vector2.ZERO),unit(1,1,Vector2(0,-3)),unit(2,1,Vector2(3,-3))]
 ck(v.resolve(4,units).is_empty(),'no early hit')
 units[1].cell=Vector2(3,-3);units[2].cell=Vector2(0.25,-3)
 var hits:Array=v.resolve(5,units)
 ck(hits.size()==1 and hits[0].target==2,'actual impact occupancy includes entrant and excludes dodger')
 ck(v.resolve(5,units).is_empty() and v.snapshot().is_empty(),'impact consumed exactly once')
 for row in [[Vector2(1.6,-2),true],[Vector2(1.601,-2),false]]:
  v.reset();v.schedule(spec('circle'));hits=v.resolve(5,[units[0],unit(1,1,row[0])])
  ck((hits.size()==1)==row[1],'circle edge includes actor radius '+str(row[0]))
 for row in [[Vector2(1.3,0.3),false],[Vector2(1.2,0.2),true]]:
  v.reset();v.schedule(spec());hits=v.resolve(5,[units[0],unit(1,1,row[0])])
  ck((hits.size()==1)==row[1],'rounded line corner geometry '+str(row[0]))
 for row in [[Vector2(0,-3.34),true],[Vector2(0,-3.36),false],[Vector2(0,1),false],[Vector2(2,-1),false]]:
  v.reset();s=spec('fan');s.radius=3.0;v.schedule(s);hits=v.resolve(5,[units[0],unit(1,1,row[0])])
  ck((hits.size()==1)==row[1],'fan radius/angular geometry '+str(row[0]))
 v.reset();s=spec();s.impacts.append({'due':6,'hit':{'source':0,'effect':'damage','ability':'ex','atk_ratio':1.0,'hit_index':1}});v.schedule(s)
 units[1].cell=Vector2(0,-3);units[2].cell=Vector2(3,-3)
 hits=v.resolve(5,units);ck(hits.size()==1 and hits[0].target==1,'first burst membership')
 units[1].cell=Vector2(3,-3);units[2].cell=Vector2(0,-3)
 hits=v.resolve(6,units);ck(hits.size()==1 and hits[0].target==2 and hits[0].hit_index==1,'later burst reevaluates membership')
 v.reset();s=spec();s.falloff={'step':0.25,'minimum':0.5};v.schedule(s)
 hits=v.resolve(5,[units[0],unit(2,1,Vector2(0,-6)),unit(1,1,Vector2(0,-3))])
 ck(hits.size()==2 and hits[0].target==1 and hits[0].atk_ratio==1.0 and hits[1].atk_ratio==0.75,'piercing ranks current targets by forward distance')
 v.reset();s=spec();s.ability='basic';s.impacts[0].hit.ability='basic';v.schedule(s);v.schedule(spec());v.cancel_cast(0,0,'basic');v.cancel_cast(0,0,'basic')
 ck(v.snapshot().size()==1 and v.snapshot()[0].ability=='ex','cancel exact cast keeps EX')
 var before:Array=v.snapshot();var bad:Dictionary=spec();bad.width=-1
 ck(v.schedule(bad)==-1 and v.snapshot()==before,'invalid width atomic')
 bad=spec();bad.origin=Vector2(NAN,0)
 ck(v.schedule(bad)==-1 and v.snapshot()==before,'nonfinite origin atomic')
 v.reset();s=spec('circle');s.impacts[0].hit={'source':0,'effect':'heal','ability':'ex','ratio':1.0};v.schedule(s)
 hits=v.resolve(5,[units[0],unit(1,1,Vector2(0,-2)),unit(2,0,Vector2(0,-2))])
 ck(hits.size()==1 and hits[0].target==2,'healing area enumerates current allies only')
 finish()
func finish()->void:
 print('TACTICAL_VOLUMES checks=',checks,' failures=',failures);quit(1 if failures else 0)
