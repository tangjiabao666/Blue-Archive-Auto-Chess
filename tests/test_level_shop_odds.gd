extends SceneTree
const Rules=preload("res://core/prototype_match.gd")
const Session=preload("res://core/game_session.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize():
 var rules=Rules.new();var catalog:Array=Session.new().catalog
 ck(rules.has_method("get_shop_odds"),"rules expose real next-roll odds without changing state")
 ck(rules.new_match(17,catalog,{"level_shop_odds":1}).ok,"level shop odds is an accepted explicit policy")
 if failures:print("LEVEL SHOP ",checks," checks FAILURES=",failures);quit(1);return
 ck(rules.snapshot().version==6,"new deterministic shop semantics use snapshot v6")
 var expected={4:[8,44,36,12],5:[8,36,36,20],6:[8,28,36,28]}
 var p:Dictionary=rules._player_ref("p0")
 for level in [4,5,6]:
  p.level=level
  var before:Dictionary=rules.snapshot();var rows:Array=rules.get_shop_odds()
  ck(rows.size()==4,"all active tiers available at every level")
  for i in range(4):
   ck(rows[i].cost==i+1 and rows[i].percent==expected[level][i],"exact candidate tier weight")
   ck(rows[i].characters==[2,4,5,3][i],"tier size is current source catalog count")
  ck(rules.snapshot()==before,"odds display consumes no random number or economy state")
  rows[0].percent=100;ck(rules.get_shop_odds()[0].percent==8,"odds result detached")
 p.level=4;p.xp=4;p.gold=100
 var old_shop:Array=p.shop.duplicate(true);var old_rng:int=rules.snapshot().rng_state
 ck(rules.execute({"type":"buy_xp"}).ok and p.level==5,"buying XP upgrades population")
 ck(p.shop==old_shop and rules.snapshot().rng_state==old_rng,"upgrade never rerolls current offers")
 ck(rules.get_shop_odds()[3].percent==20,"upgrade applies only to future refresh odds")
 var snapshot:Dictionary=rules.snapshot();var restored=Rules.new()
 ck(restored.restore(JSON.parse_string(JSON.stringify(snapshot))).ok,"odds policy survives exact JSON snapshot")
 for i in range(12):
  ck(rules.execute({"type":"refresh_shop"})==restored.execute({"type":"refresh_shop"}) and rules.snapshot()==restored.snapshot(),"restored future shops and RNG equal")
 var before:Dictionary=rules.snapshot()
 ck(not rules.execute({"type":"buy_offer","slot":-1}).ok and rules.snapshot()==before,"invalid purchase leaves weighted RNG untouched")
 for invalid in [-1,2,0.5,true,"1",null]:
  ck(not rules.new_match(17,catalog,{"level_shop_odds":invalid}).ok and rules.snapshot()==before,"invalid odds policy rejected atomically")
 var bad:Array=catalog.duplicate(true);bad[0].cost=5
 ck(not rules.new_match(17,bad,{"level_shop_odds":1}).ok and rules.snapshot()==before,"unsupported weighted tier rejected atomically")
 ck(Rules.new().new_match(17,bad,{"level_shop_odds":0}).ok,"generic uniform catalog still permits other prices")
 var older:Dictionary=before.duplicate(true);older.version=3
 ck(not rules.restore(older).ok and rules.snapshot()==before,"old snapshot explicitly rejected without mutation")
 ck(rules.get_shop_odds("missing").is_empty() and rules.snapshot()==before,"unknown read target has no effects")
 var flat=Rules.new();ck(flat.new_match(17,catalog).ok,"uniform standalone control retained")
 var rows:Array=flat.get_shop_odds()
 for row in rows:ck(is_equal_approx(row.percent,100.0*row.characters/catalog.size()),"disabled policy reports actual uniform-catalog odds")
 var one_tier:Array=catalog.duplicate(true)
 for row in one_tier:row.cost=3
 var single=Rules.new();ck(single.new_match(17,one_tier,{"level_shop_odds":1}).ok,"catalog with missing tiers remains legal")
 ck(single.get_shop_odds().size()==1 and single.get_shop_odds()[0].percent==100,"missing tiers renormalize without phantom offers")
 var game=Session.new();ck(game.new_game(17).ok and game.rules.snapshot().config.level_shop_odds==1,"playable session enables equal level odds")
 print("LEVEL SHOP ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
