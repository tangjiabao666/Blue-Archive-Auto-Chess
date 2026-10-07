extends SceneTree
const Duel=preload('res://core/offscreen_duel.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func army(key:String)->Array:return [{'character_id':key,'star':1}]
func _initialize()->void:
 var job=Duel.new();ck(job.configure(army('serika'),army('yuuka'),'p1','p2',23,{'combat_mode':'tactical_v1','max_ticks':40}).is_empty(),'source tactical duel configures')
 var sim_ref=weakref(job._simulation);var arena_ref=weakref(job._arena)
 job.advance(39)
 var raw_hp:Array=[0.0,0.0];var maximum:Array=[0.0,0.0]
 for unit in job._simulation.units:raw_hp[unit.team]+=unit.hp;maximum[unit.team]+=unit.max_hp
 ck(job.advance(1),'source duel timeout completes')
 ck(job.result.has('remaining_hp_ratios') and job.result.remaining_hp_ratios.size()==2,'completed result preserves actual HP metadata')
 var ratios:Array=job.result.remaining_hp_ratios
 ck(ratios.all(func(value):return value>=0 and value<=1),'HP ratios finite bounded')
 ck(job.result.outcome.duration_ticks==40 and job.result.outcome.size()==7,'old exact outcome schema unchanged')
 ck(sim_ref.get_ref()==null and arena_ref.get_ref()==null,'completed tactical duel releases cover callbacks and simulation')
 var copied:Dictionary=job.result;copied.remaining_hp_ratios[0]=9
 ck(job.result.remaining_hp_ratios==ratios,'HP metadata detached')
 for sides in [[[],[]],[army('serika'),[]],[[],army('yuuka')]]:
  job=Duel.new();ck(job.configure(sides[0],sides[1],'p1','p2',23,{'combat_mode':'tactical_v1'}).is_empty(),'empty-army tactical setup')
  job.run();ck(job.result.remaining_hp_ratios==[0.0 if sides[0].is_empty() else 1.0,0.0 if sides[1].is_empty() else 1.0],'empty HP derives from actual army not validation sentinels')
 job=Duel.new();job.configure(army('serika'),army('yuuka'),'p1','p2',23,{'combat_mode':'tactical_v1'})
 sim_ref=weakref(job._simulation);arena_ref=weakref(job._arena);job.cancel()
 ck(sim_ref.get_ref()==null and arena_ref.get_ref()==null,'cancelled tactical duel releases cover callbacks')
 print('TACTICAL_DUEL_HP checks=',checks,' failures=',failures);quit(1 if failures else 0)
