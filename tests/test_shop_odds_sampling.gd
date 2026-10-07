extends SceneTree
const Odds=preload("res://core/shop_odds.gd")
const Rules=preload("res://core/prototype_match.gd")
const Session=preload("res://core/game_session.gd")
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize():
 var catalog:Array=Session.new().catalog;var before:Array=catalog.duplicate(true)
 for trial in [[0,1],[7,1],[8,2],[51,2],[52,3],[87,3],[88,4],[99,4]]:
  var members:Array=catalog.filter(func(u):return u.cost==trial[1])
  var queue:Array=[trial[0],members.size()-1];var bounds:Array=[]
  var selected:Dictionary=Odds.pick(catalog,4,func(size):bounds.append(size);return queue.pop_front())
  ck(selected==members.back() and bounds==[100,members.size()] and queue.is_empty(),"exact tier boundary and uniform member bounds")
 ck(catalog==before,"sampling never changes source catalog")
 var rules=Rules.new();rules.new_match(197,catalog,{"level_shop_odds":1})
 var player:Dictionary=rules._player_ref("p0");var ai:Dictionary=rules._player_ref("p1")
 for level in [4,5,6]:
  player.level=level;ai.level=level
  rules._state.rng_state=13579;rules._roll_shop(player);var offers:Array=player.shop.duplicate(true)
  rules._state.rng_state=13579;rules._roll_shop(ai)
  ck(offers==ai.shop and rules.get_shop_odds()==rules.get_shop_odds("p1"),"AI and player use identical personal-level law")
  var counts:Dictionary={};var tier_counts:Dictionary={1:0,2:0,3:0,4:0}
  for entry in catalog:counts[entry.id]=0
  for i in range(12000):
   rules._roll_shop(player)
   for offer in player.shop:counts[offer.character_id]+=1;tier_counts[int(offer.cost)]+=1
  var rows:Array=rules.get_shop_odds()
  for row in rows:
   ck(absf(tier_counts[row.cost]/60000.0-row.percent/100.0)<0.006,"fixed-seed tier frequencies match configured weights")
   for entry in catalog:
    if entry.cost==row.cost:ck(absf(counts[entry.id]/60000.0-row.percent/100.0/row.characters)<0.006,"all same-tier characters retain uniform opportunity")
  print("SHOP_SAMPLE level=",level," n=60000 tiers=",tier_counts," characters=",counts)
 var flat=Rules.new();flat.new_match(17,catalog)
 var f:Dictionary=flat._player_ref("p0");var rng:int=12345;flat._state.rng_state=rng
 for roll in range(20):
  var expected:Array=[]
  for slot in range(5):
   rng=(rng*48271)%2147483647;var entry:Dictionary=catalog[rng%catalog.size()];expected.append({"character_id":entry.id,"cost":entry.cost})
  flat._roll_shop(f);ck(f.shop==expected and flat._state.rng_state==rng,"uniform control retains exact legacy single RNG draw")
 print("SHOP SAMPLING ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
