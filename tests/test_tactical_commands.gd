extends SceneTree
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr('FAIL '+label)
func command(sequence:int=1,team:int=0,at:int=1)->Dictionary:
 return {'generation':7,'team':team,'sequence':sequence,'tick':at,'type':'cast_ex','actor_id':10 if team==0 else 20,'target_id':20 if team==0 else 10,'point':Vector2(1,2)}
func _initialize()->void:
 var path:='res://core/tactical_command_queue.gd'
 ck(FileAccess.file_exists(path),'tactical command queue exists')
 if failures:finish();return
 var q=load(path).new();q.reset(7)
 ck(q.configure_actors([{'id':10,'team':0},{'id':20,'team':1}]).ok,'configure actor ownership')
 var empty:Dictionary=q.snapshot()
 for patch in [{'generation':6},{'team':1},{'actor_id':999},{'tick':0},{'tick':6},{'point':Vector2(NAN,0)},{'point':Vector2(INF,0)},{'sequence':-1},{'sequence':1.5},{'type':'delete'},{'target_id':-2},{'extra':1}]:
  var bad:Dictionary=command();bad.merge(patch,true)
  ck(not q.enqueue(bad,0).ok,'reject invalid '+str(patch))
  ck(q.snapshot()==empty,'invalid leaves queue unchanged '+str(patch))
 var missing:Dictionary=command();missing.erase('point')
 ck(not q.enqueue(missing,0).ok and q.snapshot()==empty,'missing field rejected without mutation')
 var original:Dictionary=command(2)
 ck(q.enqueue(original,0).ok,'accept valid command')
 original.point=Vector2(999,999)
 var before:Dictionary=q.snapshot()
 ck(not q.enqueue(command(2),0).ok and q.snapshot()==before,'duplicate has no state effect')
 ck(q.enqueue(command(1),0).ok,'accept out-of-order sequence before dispatch')
 ck(q.enqueue(command(1,1),0).ok,'sequence scoped to team')
 var second:Dictionary=command(3,0,2);second.type='move';second.target_id=-1
 ck(q.enqueue(second,0).ok,'queue next tick move')
 ck(q.drain(0).is_empty(),'future commands not executed early')
 var batch:Array=q.drain(1)
 ck(batch.size()==3,'drain due commands only')
 if batch.size()==3:
  ck(batch[0].team==0 and batch[0].sequence==1 and batch[1].sequence==2 and batch[2].team==1,'canonical team then sequence ordering')
  ck(batch[1].point==Vector2(1,2),'input detached from caller')
 ck(q.drain(1).is_empty(),'repeat drain cannot replay')
 ck(not q.enqueue(command(2,0,2),1).ok,'consumed sequence cannot replay later')
 ck(q.drain(2).size()==1,'later tick independently drains')
 var state:Dictionary=q.snapshot();state.pending.append(command(99))
 ck(q.snapshot().pending.is_empty(),'snapshot detached')
 before=q.snapshot()
 ck(not q.configure_actors([{'id':10,'team':0},{'id':10,'team':1}]).ok and q.snapshot()==before,'duplicate ownership rejected atomically')
 q.reset(8)
 ck(q.snapshot().pending.is_empty() and q.snapshot().seen.is_empty(),'reset clears previous battle')
 ck(not q.enqueue(command(4),2).ok,'old generation cannot enter new battle')
 ck(q.configure_actors([{'id':10,'team':0},{'id':20,'team':1}]).ok,'rebind reset actor ownership')
 var fresh:Dictionary=command();fresh.generation=8
 ck(q.enqueue(fresh,0).ok,'same sequence usable in new generation')
 finish()
func finish()->void:
 print('TACTICAL_COMMANDS checks=',checks,' failures=',failures)
 quit(1 if failures else 0)
