extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const Presenter=preload("res://core/combat_status_presenter.gd")
const Legacy=preload("res://tests/fixtures/asuna_status/legacy_presenter.gd")
const Strip=preload("res://scripts/combat_status_strip.gd")
var checks:=0
var failures:=0
func ck(ok:bool,message:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",message)
func effect(state:Dictionary,id:String)->Dictionary:
 for item in state.effects:
  if item.id==id:return item
 return {}
func _initialize():call_deferred("run")
func run():
 var p=Presenter.new();var sim=Sim.new();var definition:Dictionary=sim.character_data("asuna")
 var a:Dictionary=sim.preview_unit("asuna",1)
 ck(p.present(a,0,definition).ex.kind=="locked","one-star EX stays locked")
 a.star=2;a.skill_ready=100;a.skill_cooldown_ticks=300;a.basic_ready=400
 var state:Dictionary=p.present(a,40,definition)
 ck(state.ex.remaining_seconds==3.0 and state.basic.remaining_seconds==18.0,"EX and basic use actual independent tick countdowns")
 ck(state.sub.kind=="condition" and state.sub.text=="EX" and state.sub.remaining_seconds==0,"sub triggers on EX without an invented cooldown")
 ck(p.present(a,100,definition).ex.kind=="ready","elapsed EX is ready")
 ck(p.present(a,0,definition,true).ex.kind=="preparation","preparation pauses EX display")
 ck(sim.configure([{"id":0,"team":0,"character_id":"asuna","star":2,"cell":Vector2(0,3)},{"id":1,"team":1,"character_id":"yuuka","star":1,"cell":Vector2(0,-3)}],{"random_damage":false}).is_empty(),"Asuna isolated fixture configures")
 sim.start();a=sim.units[0]
 for u in sim.units:
  u.attack_ready=100000;u.aim_ready=100000;u.basic_ready=100000;u.skill_ready=100000
  if u.id!=0:u.busy_until=100000
 ck(sim._try_skill(a,"ex"),"EX accepted")
 var before:Dictionary=a.duplicate(true);var def_before:Dictionary=definition.duplicate(true)
 state=p.present(a,sim.tick,definition)
 ck(a==before and definition==def_before,"presenter does not mutate simulation data")
 ck(state.effects.size()==2,"cast start exposes only separate EX/sub speed buffs")
 var ex:Dictionary=effect(state,"asuna_ex_attack_speed");var sub:Dictionary=effect(state,"asuna_sub_attack_speed")
 ck(ex.get("hint","").contains("EX · 攻击速度 +57.37%") and ex.get("seconds",0)==30.0,"EX speed tooltip identifies exact active value and duration")
 ck(sub.get("hint","").contains("子技能 · 攻击速度 +38.31%") and sub.get("seconds",0)==30.0,"sub speed tooltip identifies exact independent value and duration")
 ck(ex.get("label","")!=sub.get("label",""),"text fallback distinguishes EX/sub buffs")
 var strip=Strip.new();root.add_child(strip);strip.update_unit(a,sim.tick,definition)
 ck(strip.icons.effect_key({"id":"asuna_ex_dash_evasion"},{},0)=="","dash glyph is absent without authoritative buff")
 ck(strip.icons.effect_key({"id":"asuna_ex_dash_evasion"},{"asuna_ex_dash_evasion":{"stat":"DodgePoint","fraction":-0.4341}},0)=="","negative evade does not use a positive buff glyph")
 ck(strip.icons.effect_key({"id":"asuna_ex_dash_evasion"},{"asuna_ex_dash_evasion":{"stat":"AttackPower","fraction":0.2}},0)=="buff/Buff_ATK","canonical ID with wrong stat falls back to actual stat")
 ck(strip.icons.effect_key({"id":"legacy_dodge"},{"legacy_dodge":{"stat":"DodgePoint","fraction":0.2}},0)=="","unrelated evade buff projection keeps prior text fallback")
 ck(strip.skill_icon_keys==["skill/COMMON_SKILLICON_EVASION","skill/COMMON_SKILLICON_TARGET","skill/COMMON_SKILLICON_WEAPONBUFF"],"Asuna uses all three source skill glyphs")
 ck(strip.effect_icon_keys==["buff/Buff_AttackSpeed","buff/Buff_AttackSpeed"],"both independent speed badges reuse verified buff glyph")
 for i in range(8):sim.step()
 state=p.present(a,sim.tick,definition)
 var dodge:Dictionary=effect(state,"asuna_ex_dash_evasion")
 ck(dodge.get("hint","").contains("EX 冲刺 · 闪避值 +43.41%") and dodge.get("hint","").contains("仅冲刺位移期间"),"evasion tooltip has exact amount and movement-only condition")
 ck(not dodge.get("hint","").contains("30") and is_equal_approx(dodge.get("seconds",0.0),1.6),"evasion uses actual dash remainder, never the speed buff duration")
 strip.update_unit(a,sim.tick,definition)
 ck(strip.display_effects.size()==3 and strip.effect_icon_keys==["buff/Buff_AttackSpeed","buff/Buff_Dodge","buff/Buff_AttackSpeed"],"three live Asuna buffs retain separate small badges")
 for key in strip.skill_icon_keys+strip.effect_icon_keys:ck(strip._has_icon(key),"verified Asuna icon is loadable: "+key)
 var revision:int=strip.revisions;strip.update_unit(a,sim.tick,definition)
 ck(strip.revisions==revision,"unchanged tick does not redraw cached Asuna status")
 a.stun_until=20;sim.step();strip.update_unit(a,sim.tick,definition)
 ck(effect(strip.status,"asuna_ex_dash_evasion").is_empty(),"dash interruption removes evasion badge immediately")
 ck(not effect(strip.status,"asuna_ex_attack_speed").is_empty() and not effect(strip.status,"asuna_sub_attack_speed").is_empty(),"interruption retains the two separate speed buffs")
 state=p.present(a,600,definition)
 ck(effect(state,"asuna_ex_attack_speed").is_empty() and effect(state,"asuna_sub_attack_speed").is_empty(),"speed badges expire at authoritative exclusive boundary")
 # Same-tick removal refreshes cached strip; presentation must never recreate state.
 a.buffs={};strip.update_unit(a,sim.tick,definition)
 ck(effect(strip.status,"asuna_ex_attack_speed").is_empty(),"same-tick buff cleanup refreshes strip")
 a.hp=0;strip.update_unit(a,sim.tick,definition);ck(not strip.visible,"dead Asuna hides status strip")
 strip.free()
 # Original 13 projections remain identical across status, cooldown, and preparation cases.
 var legacy=Legacy.new();var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character_skills.json"))
 ck(data.active_roster.size()==14 and data.active_roster.back()=="asuna","Asuna appended after original thirteen")
 for key in data.active_roster:
  if key=="asuna":continue # Separate Asuna checks above; this is frozen original-13 parity.
  var u:Dictionary=sim.preview_unit(key,2);var d:Dictionary=sim.character_data(key)
  for tick in [0,40,600]:
   for preparation in [false,true]:
    u.buffs={"test":{"stat":"AttackSpeed","fraction":0.5737,"until":600},"stationary":{"stat":"AttackPower","fraction":0.26,"condition":"while_stationary","until":100000}}
    u.skill_ready=100;u.basic_ready=150;u.sub_ready=200;u.shield=500;u.shield_until=90;u.stun_until=60;u.taunt_until=80;u.charges=2
    ck(p.present(u,tick,d,preparation)==legacy.present(u,tick,d,preparation),"legacy projection parity: "+key)
 print("ASUNA_STATUS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
