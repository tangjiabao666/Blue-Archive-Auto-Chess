extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const Presenter=preload("res://core/recruitment_skill_presenter.gd")
var checks:=0
var fails:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:fails+=1;printerr("FAIL: "+label)
func _initialize():
 var sim=Sim.new();var before:Dictionary=sim.snapshot()
 var result:Dictionary=Presenter.describe(sim,"asuna","明日奈",1,5.0)
 ck(result.ok and result.cost==1,"Asuna is recruitable at explicit one-gold adaptation")
 var ex:Dictionary={}
 for row in result.skills:
  ck(not row.text.contains(Presenter.UNKNOWN),"Asuna skill understood: "+row.slot)
  if row.slot=="ex":ex=row
 for word in ["冲刺","57.37%","30s","43.41%","实际","15s","2★"]:
  ck(str(ex.get("text","")).contains(word),"EX source/adaptation description: "+word)
 ck(sim.snapshot()==before,"recruitment preview preserves all simulation and RNG")
 var changed:Dictionary=sim.character_data("asuna").ex
 changed.bonusFraction=0.1234;changed.durationSeconds=17;changed.evasion.bonusFraction=0.2345
 var text:String=Presenter._effect_text(changed,"asuna",sim.options)
 ck(text.contains("12.34%") and text.contains("17s") and text.contains("23.45%"),"description derives coefficients and duration from source fields")
 print("ASUNA RECRUITMENT CHECKS=",checks," FAILURES=",fails);quit(1 if fails else 0)
