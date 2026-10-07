extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func volume(id:int,shape:String)->Dictionary:return {'id':id,'source':0,'team':1,'ability':'ex','cast_start_tick':0,'shape':shape,'origin':Vector2.ZERO,'direction':Vector2.UP,'centers':[Vector2(0,-2)],'radius':1.25,'width':2.0,'length':10.0,'degrees':60.0,'impacts':[{'due':40,'hit':{'effect':'damage'}}]}
func _initialize()->void:call_deferred('run')
func run()->void:
 var path:='res://scripts/attack_telegraphs.gd';ck(FileAccess.file_exists(path),'telegraph renderer exists')
 if failures:finish();return
 var view=load(path).new();root.add_child(view)
 var a:Dictionary=volume(1,'circle');var b:Dictionary=volume(2,'line')
 view.update_volumes([a,b],0.0)
 ck(view.tracked_count()==2,'visible warnings tracked')
 ck(view.geometry_builds==2,'initial shapes built once')
 view.update_volumes([a,b],0.1)
 ck(view.geometry_builds==2,'frame updates reuse geometry')
 var outlines:Array=load('res://core/attack_volumes.gd').outline(a,0.35)
 var max_x:float=-INF
 for point in outlines[0]:max_x=maxf(max_x,point.x)
 ck(absf(max_x-1.6)<0.005,'warning radius matches hitbox-dilated circle')
 view.update_volumes([a],0.2);ck(view.tracked_count()==1,'resolved warning removed')
 view.reset();ck(view.tracked_count()==0,'reset clears prior generation shapes')
 var stage=load('res://scripts/battle_stage.gd').new()
 ck(stage.has_method('update_attack_telegraphs'),'battle stage exposes authoritative warning update')
 if stage.has_method('update_attack_telegraphs'):
  stage.preparation=false;stage.update_attack_telegraphs([a],0.1)
  ck(stage._attack_telegraphs.tracked_count()==1,'stage forwards shape snapshot')
  stage.preparation=true;stage.update_attack_telegraphs([a],0.1)
  ck(stage._attack_telegraphs.tracked_count()==0,'preparation suppresses stale battle warnings')
 stage.free();view.queue_free();await process_frame;finish()
func finish()->void:
 print('TACTICAL_TELEGRAPHS checks=',checks,' failures=',failures);quit(1 if failures else 0)
