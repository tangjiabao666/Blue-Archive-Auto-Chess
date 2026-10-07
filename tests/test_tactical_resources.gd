extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 var path:='res://core/tactical_resources.gd';ck(FileAccess.file_exists(path),'shared tactical resources exist')
 if failures:finish();return
 var r=load(path).new();r.reset()
 ck(r.snapshot().teams[0].energy==4 and r.snapshot().teams[1].energy==4,'both teams begin4')
 r.advance(39);ck(r.snapshot().teams[0].energy==4,'no early regen')
 r.advance(40);ck(r.snapshot().teams[0].energy==5,'one energy after40ticks')
 ck(r.commit_cast(0,10,3,40),'cast spends valid cost')
 ck(r.snapshot().teams[0].energy==2 and r.snapshot().teams[1].energy==5,'team resources isolated')
 var before:Dictionary=r.snapshot()
 ck(not r.commit_cast(0,10,1,40) and r.snapshot()==before,'same actor cooldown atomic')
 ck(not r.commit_cast(0,11,3,40) and r.snapshot()==before,'second cast cannot overspend')
 for invalid in [[2,10,1,40],[0,-1,1,40],[0,11,0,40],[0,11,-1,40],[0,11,11,40],[0,11,1,39]]:
  ck(not r.commit_cast(invalid[0],invalid[1],invalid[2],invalid[3]) and r.snapshot()==before,'invalid spend unchanged '+str(invalid))
 r.advance(159);ck(not r.can_cast(0,10,1,159),'cooldown not early')
 r.advance(160);ck(r.can_cast(0,10,1,160),'ready exactly120ticks later')
 r.advance(1000);ck(r.snapshot().teams[0].energy==10,'energy capped')
 before=r.snapshot();r.advance(999);ck(r.snapshot()==before,'rewind ignored')
 var detached:Dictionary=r.snapshot();detached.teams[0].energy=999
 ck(r.snapshot().teams[0].energy==10,'snapshot detached')
 r.reset();ck(r.can_move(0) and r.snapshot().teams[0].moves==2,'two move charges')
 r.advance(119);ck(r.commit_move(0) and r.commit_move(0),'two charges consumed')
 before=r.snapshot();ck(not r.commit_move(0) and r.snapshot()==before,'no extra movement spend')
 r.advance(120);ck(not r.can_move(0),'move recharge starts at consumption not global phase')
 r.advance(238);ck(not r.can_move(0),'move recharge not early')
 r.advance(239);ck(r.snapshot().teams[0].moves==1,'one charge restored120ticks afterspend')
 r.advance(359);ck(r.snapshot().teams[0].moves==2,'second charge restored')
 r.advance(1000);ck(r.snapshot().teams[0].moves==2,'move cap2')
 r.reset();ck(r.snapshot().teams[0].energy==4 and r.snapshot().ready.is_empty(),'round reset clears prior resources and cooldowns')
 finish()
func finish()->void:
 print('TACTICAL_RESOURCES checks=',checks,' failures=',failures);quit(1 if failures else 0)
