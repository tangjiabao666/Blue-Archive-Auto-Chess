extends SceneTree
const Sim=preload("res://core/character_sim.gd")
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr("FAIL: "+label)
func fixture(key:String,star:int=1):
	var s=Sim.new();s.configure([{"id":0,"team":0,"cell":Vector2(0,2),"character_id":key,"star":star},{"id":1,"team":1,"cell":Vector2(0,-2),"character_id":"yuuka","star":1}],{"random_damage":false});s.start();s.tick=10;return s
func _initialize():
	# Every normal burst preserves exact sum, ammo cost, source damage type and deterministic cadence.
	for key in ["iori","tsubaki","nonomi","mutsuki","haruna"]:
		var s=fixture(key);var u=s.units[0];var c=s.character_data(key);var before:int=u.ammo
		s._normal_attack(u,s.units[1]);var ratio:=0.0
		for hit in s._pending:ratio+=hit.atk_ratio
		ck(absf(ratio-c.normalAttack.totalAtkRatioPerBurst)<0.00001,key+" normal aggregate coefficient")
		ck(u.ammo==before-c.normalAttack.ammoConsumedPerBurst,key+" source ammo cost")
		ck(u.attack_ready==10+s._ticks(c.normalAttack.burstPeriodSecondsBeforePassives),key+" source burst cooldown")
		ck(u.damage_type==c.damageType,key+" source damage type")
	# Mutsuki proc is a per-burst adaptation, source chance and internal cooldown remain exact.
	var s=fixture("mutsuki");var u=s.units[0]
	for i in range(50):
		u.ammo=45;s._normal_attack(u,s.units[1])
		if u.buffs.has("mutsuki_sub"):break
	ck(u.buffs.has("mutsuki_sub"),"seeded Mutsuki accuracy proc activates")
	if u.buffs.has("mutsuki_sub"):
		ck(u.sub_ready==510 and u.buffs.mutsuki_sub.until==610,"Mutsuki source 25s ICD and 30s buff duration")
		ck(u.buffs.mutsuki_sub.stat=="AccuracyPoint" and is_equal_approx(u.buffs.mutsuki_sub.fraction,0.5746),"Mutsuki proc buffs accuracy rather than attack speed")
		var state:int=s._rng.state;var count:int=s.events.size()
		for i in range(50):u.ammo=45;s._normal_attack(u,s.units[1])
		ck(s._rng.state==state,"Mutsuki cooldown blocks additional proc RNG rolls")
		ck(s.events.filter(func(e):return e.type=="buff").size()==1,"Mutsuki proc does not refresh during internal cooldown")
	# Nonomi periodic stat increase expires on its exact boundary.
	s=fixture("nonomi");u=s.units[0];s._try_skill(u,"basic")
	ck(u.basic_ready==610,"Nonomi independent 30s basic cooldown")
	if u.buffs.has("nonomi_basic"):
		s.tick=u.buffs.nonomi_basic.until;s._expire_and_reload()
		ck(not u.buffs.has("nonomi_basic") and s.stat(u,"AttackPower")==u.base_stats.AttackPower,"Nonomi buff expires after exact 20s")
	# Haruna falloff clamps, never compounds. IDs do not define projectile order.
	s=fixture("haruna");u=s.units[0];u.cell=Vector2(0,6);s.units[1].cell=Vector2(0,5)
	for i in range(8):s.units.append(s.preview_unit("yuuka",1,10+i,1,Vector2(0,4-i)))
	s._try_skill(u,"ex")
	ck(s._pending.size()==9,"Haruna geometry contains every collinear target")
	for i in range(s._pending.size()):ck(is_equal_approx(s._pending[i].atk_ratio,8.8719*maxf(0.3,1.0-0.1*i)),"Haruna linear falloff floors at 30 percent")
	for star in [1,2]:
		u=s.preview_unit("haruna",star)
		ck(u.hp==u.max_hp and u.stats.MaxHP==u.max_hp,"Haruna constructor and preview agree on enhanced max HP")
		ck(u.max_hp==(14879 if star==1 else 17855),"Haruna enhanced HP not double counted")
	print("EXPANDED CHARACTER COEFFICIENTS FAILURES=",fails);quit(1 if fails else 0)
