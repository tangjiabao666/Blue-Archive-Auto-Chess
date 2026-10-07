extends SceneTree
const Sim=preload("res://core/character_sim.gd")
var fails:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok: fails+=1;printerr("FAIL: "+label)
func fixture(star:int=2):
 var s=Sim.new()
 ck(s.configure([{"id":0,"team":0,"character_id":"asuna","star":star,"cell":Vector2(0,3)},{"id":1,"team":1,"character_id":"yuuka","star":1,"cell":Vector2(0,-3)}],{"random_damage":false}).is_empty(),"configure Asuna")
 s.start()
 for u in s.units:
  u.attack_ready=100000;u.aim_ready=100000;u.aimed=true;u.basic_ready=100000;u.skill_ready=100000
  if u.id!=0:u.busy_until=100000
 return s
func _initialize():
 var s=fixture();var a=s.units[0]
 ck(s.stat(a,"CriticalDamageRate")==25320,"enhanced affects critical damage, not chance")
 ck(a.max_hp==16928 and s.stat(a,"AttackPower")==2125,"merged source stats")
 ck(a.skill_cooldown_ticks==300 and a.skill_recovery_ticks==53,"EX adapted cooldown/source lock")
 var rng=s._rng.state
 ck(s._try_skill(a,"ex"),"accept source dash EX")
 if s.events.any(func(e):return e.type=="skill_unavailable"):
  finish();return
 ck(s._rng.state==rng,"EX consumes no RNG")
 ck(s._pending.is_empty(),"EX schedules no attacks")
 ck(a.ammo==15 and a.reload_until==0,"EX does not refill or reload")
 ck(s.stat(a,"AttackSpeed")==19568,"separate additive EX and sub attack-speed buffs")
 ck(s.stat(a,"DodgePoint")==778,"no evasion before actual dash")
 ck(a.buffs.has("asuna_ex_attack_speed") and a.buffs.has("asuna_sub_attack_speed"),"distinct speed buff IDs")
 var total:=0
 for i in range(7):
  s.step();ck(a.cell==Vector2(0,3),"hold through pre-dash tick %d"%s.tick)
 for i in range(32):
  var batch=s.step()
  total+=batch.filter(func(e):return e.type=="dash_move").size()
  ck(s.stat(a,"DodgePoint")==1116,"evasion during actual dash %d"%s.tick)
  ck(a.cell.distance_to(s.units[1].cell)>=0.699999,"dash does not overlap enemy")
 ck(total==32 and a.cell.is_equal_approx(Vector2(0,1)),"32 steps move two world units")
 s.step();ck(s.stat(a,"DodgePoint")==778,"evasion ends at exclusive end")
 ck(s.events.any(func(e):return e.type=="dash_finished"),"finish event emitted")
 ck(s.stat(a,"AttackSpeed")==19568,"speed remains after movement")
 # Static blocking still accepts EX and keeps speed, but never gives movement evasion.
 s=fixture();a=s.units[0];s.segment_free=func(_from,_to,_radius):return false
 ck(s._try_skill(a,"ex"),"blocked dash still casts self-buff")
 for i in range(41):s.step()
 ck(a.cell==Vector2(0,3) and s.stat(a,"DodgePoint")==778,"blocked cast never moves or retains evade")
 # Mid-dash stun interrupts permanently, not pause/resume.
 s=fixture();a=s.units[0];s._try_skill(a,"ex")
 for i in range(10):s.step()
 var stopped:Vector2=a.cell;a.stun_until=20
 s.step();ck(a.cell==stopped and s.stat(a,"DodgePoint")==778,"stun cancels movement/evasion")
 for i in range(30):s.step()
 ck(a.cell==stopped,"cancelled dash never resumes")
 # Less than .001 world units is not a useful dash and grants no dodge window.
 s=fixture();a=s.units[0];s.units[1].cell=Vector2(0,2.29996);s._try_skill(a,"ex")
 for i in range(8):s.step()
 ck(s.stat(a,"DodgePoint")==778 and a.cell==Vector2(0,3),"microscopic blocked movement grants no evasion")
 # Self-buff gameplay targeting still carries real direction for presentation.
 s=fixture();a=s.units[0];s.units[1].cell=Vector2(3,-3);s._try_skill(a,"ex")
 var casts:Array=s.events.filter(func(e):return e.type=="skill")
 ck(casts.size()==1 and casts[0].target_cell==Vector2(3,-3) and casts[0].get("reference_target_id",-1)==1,"EX presentation faces frozen enemy reference")
 # A landed stun cancels evasion before another hit in the same tick.
 s=fixture();a=s.units[0];s._try_skill(a,"ex")
 for i in range(10):s.step()
 s._normal_attack(s.units[1],a)
 var stun_hit:Dictionary=s._pending[0].duplicate(true);stun_hit.stun_seconds=1.0
 s._resolve_hit(stun_hit)
 ck(a.stun_until>s.tick and s.stat(a,"DodgePoint")==778,"landed stun clears evasion immediately")
 # Rejected no-enemy casts do not consume resources or emit an ability.
 s=fixture();a=s.units[0];s.units[1].hp=0
 var before_cd:int=a.skill_ready;var before_rng=s._rng.state
 ck(not s._try_skill(a,"ex") and a.skill_ready==before_cd and a.buffs.is_empty() and s._rng.state==before_rng,"no-enemy EX rejected transactionally")
 # Destination is selected once; a new windup obstacle cancels instead of retargeting.
 s=fixture();a=s.units[0];var blocked:=[false]
 s.segment_free=func(_from,to,_radius):return not blocked[0] or to.y>=2.0
 s._try_skill(a,"ex");blocked[0]=true
 for i in range(9):s.step()
 ck(a.cell==Vector2(0,3) and s.stat(a,"DodgePoint")==778,"windup obstruction cancels frozen path")
 # Death clears all three Asuna combat buffs, even after movement has finished.
 for death_tick in [10,45]:
  s=fixture();a=s.units[0];s._try_skill(a,"ex")
  for i in range(death_tick):s.step()
  a.hp=0;s.step()
  ck(not a.buffs.has("asuna_ex_attack_speed") and not a.buffs.has("asuna_sub_attack_speed") and not a.buffs.has("asuna_ex_dash_evasion"),"death clears combat buffs %d"%death_tick)
 s=fixture();a=s.units[0];s._try_skill(a,"ex");s._refresh_stats();s._end(0,"fixture")
 ck(a.buffs.is_empty(),"round finish clears Asuna buffs")
 ck(a.stats.AttackSpeed==10000 and a.stats.DodgePoint==778,"round finish cached stats match removed buffs")
 # Basic preserves all eleven literal source weights and legacy timing.
 s=fixture(1);a=s.units[0];ck(s._try_skill(a,"basic"),"basic casts at one star")
 ck(s._pending.size()==11 and a.busy_until==60 and a.basic_ready==400,"basic eleven hits/source timers")
 var expected:=[12,16,20,24,28,32,35,39,43,47,51]
 for i in range(s._pending.size()):
  ck(s._pending[i].due==expected[i],"legacy dispatch offset %d"%i)
  ck(is_equal_approx(s._pending[i].atk_ratio,4.1641*0.0909),"raw non-normalized weight %d"%i)
 finish()
func finish():
 print("ASUNA MECHANICS CHECKS=",checks," FAILURES=",fails);quit(1 if fails else 0)
