extends SceneTree
const Sim=preload("res://core/character_sim.gd")
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr("FAIL: "+label)
func near(a:float,b:float)->bool:return absf(a-b)<0.00001
func sim_for(key:String,star:int=2):
	var s=Sim.new()
	ck(s.configure([{"id":0,"team":0,"cell":Vector2(0,2),"character_id":key,"star":star},{"id":1,"team":1,"cell":Vector2(0,-2),"character_id":"yuuka","star":1}],{"random_damage":false}).is_empty(),"fixture configure "+key)
	s.start();s.tick=10
	for u in s.units:u.basic_ready=100000;u.skill_ready=100000;u.attack_ready=100000;u.aim_ready=100000;u.aimed=true
	return s
func add_enemy(s,id:int,cell:Vector2):
	var u=s.preview_unit("yuuka",1,id,1,cell);u.hp=1000000;u.max_hp=1000000;u.busy_until=100000;s.units.append(u);return u
func damage_hits(s)->Array:return s._pending.filter(func(h):return h.effect=="damage")
func events_of(s,kind:String)->Array:return s.events.filter(func(e):return e.type==kind)
func _initialize():
	var s=Sim.new()
	for key in ["iori","tsubaki","nonomi","mutsuki","haruna"]:ck(s.character_keys().has(key),"registered source record "+key)
	# Iori: three independent full-strength shots, rear fan begins at primary target.
	s=sim_for("iori");add_enemy(s,2,Vector2(0,-3));add_enemy(s,3,Vector2(2,-3))
	ck(s._try_skill(s.units[0],"ex"),"Iori EX starts")
	var hits=damage_hits(s);ck(hits.size()==6,"Iori damages primary and rear fan once each across 3 shots")
	for h in hits:ck(h.target in [1,2] and near(h.atk_ratio,6.6629),"Iori geometry/coefficient preserves full per-shot damage")
	ck(s.units[0].skill_ready==410,"Iori independent 20-second EX cooldown")
	# Haruna line order is projectile order, independent of unit id.
	s=sim_for("haruna");s.units[1].cell=Vector2(0,-4);add_enemy(s,2,Vector2(0,-1));add_enemy(s,3,Vector2(1,-2))
	s._try_skill(s.units[0],"ex");hits=damage_hits(s)
	ck(hits.size()==2,"Haruna line excludes off-line enemy")
	if hits.size()==2:
		ck(hits[0].target==2 and near(hits[0].atk_ratio,8.8719),"Haruna first projectile target gets full damage")
		ck(hits[1].target==1 and near(hits[1].atk_ratio,8.8719*0.9),"Haruna subsequent target loses 10 percent")
	ck(s.units[0].max_hp==ceili(14879*1.2),"Haruna enhanced MaxHP applied once before merge")
	ck(near(s.stat(s.units[0],"AttackPower"),3565),"Haruna stationary attack buff present")
	# Nonomi basic is a timed attack buff; EX is two half-weight hits per fan victim.
	s=sim_for("nonomi");s._try_skill(s.units[0],"basic")
	ck(s.units[0].buffs.has("nonomi_basic"),"Nonomi basic buff stored for HUD")
	ck(near(s.stat(s.units[0],"AttackPower"),round(s.units[0].base_stats.AttackPower*1.4149*1.2)),"Nonomi attack buff changes actual damage stat")
	s._pending=[];s._try_skill(s.units[0],"ex");hits=damage_hits(s)
	ck(hits.size()==2,"Nonomi EX keeps two native damage weights")
	for h in hits:ck(near(h.atk_ratio,8.2179*0.5),"Nonomi EX aggregate coefficient not multiplied twice")
	# Tsubaki EX has defense and hostile targeting, no synthetic shield or damage.
	s=sim_for("tsubaki");var taunter=s.units[0];var victim=s.units[1]
	var ally=s.preview_unit("yuuka",1,3,0,Vector2(0,-1));ally.busy_until=100000;s.units.append(ally)
	s._try_skill(taunter,"ex")
	ck(taunter.buffs.has("tsubaki_ex"),"Tsubaki defense buff stored")
	ck(victim.get("taunt_source_id",-1)==0 and victim.get("taunt_until",0)==134,"Tsubaki six-point-two-second taunt recorded")
	ck(s._target(victim).id==0,"taunt overrides closer enemy")
	ck(taunter.shield==0 and damage_hits(s).is_empty(),"Tsubaki defense is not barrier or damage")
	var raw_before=s.damage_components(victim,taunter,1).raw
	s._start_reload(taunter)
	ck(near(s.damage_components(victim,taunter,1).raw/raw_before,0.544),"Tsubaki reload reduces incoming damage by exactly 45.6 percent")
	ck(taunter.buffs.has("tsubaki_reload"),"Tsubaki reload reduction exposed to HUD")
	# Unknown kinds cannot silently spend cooldown and claim a successful cast.
	s=sim_for("iori");s._characters.iori.ex.kind="unsupported_source_semantic"
	ck(not s._try_skill(s.units[0],"ex"),"unknown semantic rejected")
	ck(s.units[0].skill_ready==100000,"unknown semantic cannot consume cooldown")
	# Source-null Mutsuki geometry is explicit runtime adaptation, mines persist.
	s=sim_for("mutsuki");s._try_skill(s.units[0],"basic")
	ck(damage_hits(s).is_empty(),"Mutsuki mine placement never becomes immediate generic damage")
	ck(s._pending.any(func(h):return h.effect=="place_mines"),"Mutsuki schedules persistent mine placement")
	s._pending=[];s._try_skill(s.units[0],"ex");hits=damage_hits(s)
	ck(not hits.is_empty(),"Mutsuki three-circle EX queues real area damage")
	for h in hits:ck(near(h.atk_ratio,7.7849),"Mutsuki each area is full coefficient")
	print("EXPANDED CHARACTER MECHANICS FAILURES=",fails);quit(1 if fails else 0)
