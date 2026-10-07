extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func offer(app,slot:int,key:String="shiroko",cost:int=2)->void:
	app.session.rules._player_ref("p0").shop[slot]={"character_id":key,"cost":cost}
func run()->void:
	var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=false;root.add_child(app);app.set_process(false)
	ck(app.shop_cards[0].has("progress"),"shop cards expose owned one-star progress")
	if failures:app.free();finish();return
	app.act({"type":"restart","seed":17})
	var p:Dictionary=app.session.rules._player_ref("p0");p.gold=100
	for slot in range(5):offer(app,slot)
	app._refresh_ui()
	var before:Dictionary=app.session.rules.snapshot()
	app._refresh_ui()
	ck(app.session.rules.snapshot()==before,"UI hints leave offers, gold, RNG and all match state unchanged")
	ck(app.shop.size()==5,"five-card compact layout retained")
	for slot in range(5):
		var button:Button=app.shop[slot];var card:Dictionary=app.shop_cards[slot]
		ck(button.position==Vector2(30+slot*187,761) and button.size==Vector2(175,105),"card geometry unchanged")
		ck(card.art.position==Vector2(2,2) and card.art.size==Vector2(85,101) and card.art.texture!=null,"original portrait and geometry retained")
		ck(card.progress.position==Vector2(90,82) and card.progress.size==Vector2(80,20),"progress fits below existing price: actual %s %s minimum %s"%[card.progress.position,card.progress.size,card.progress.get_minimum_size()])
		ck(card.progress.text=="一星 0/3" and card.progress.visible and card.price.text=="2 金币","all matching offers show accurate initial count and original price")
		ck(card.progress.mouse_filter==Control.MOUSE_FILTER_IGNORE,"progress overlay cannot intercept purchase clicks")
		ck(card.progress.position.y>=card.price.position.y+card.price.size.y and card.progress.position.y+card.progress.size.y<=button.size.y-3,"progress has no price overlap and retains bottom padding")
	var bought:Dictionary=app.act({"type":"buy_offer","slot":0});ck(bought.ok,"first matching purchase succeeds")
	ck(app.shop_cards[1].progress.text=="一星 1/3","purchase updates other matching shop cards")
	ck(not app.shop_cards[0].progress.visible and app.shop_cards[0].progress.text.is_empty() and app.shop[0].tooltip_text.is_empty(),"sold card clears stale progress and tooltip")
	ck(app.act({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"one matching copy deploys")
	ck(app.shop_cards[1].progress.text=="一星 1/3","deployment does not remove owned progress")
	var second:Dictionary=app.act({"type":"buy_offer","slot":1});ck(second.ok,"second matching purchase succeeds")
	ck(app.shop_cards[2].progress.text=="一星 2/3","board plus bench pair appears on remaining offers")
	ck(app.refresh_button.tooltip_text.contains("刷新 2 + 再购买 1 张 2 = 4 金币") and app.refresh_button.tooltip_text.contains("一星 2/3"),"selected target budget follows new purchase")
	var merged:Dictionary=app.act({"type":"buy_offer","slot":2});ck(merged.ok,"third matching purchase merges normally")
	ck(app.shop_cards[3].progress.text=="仅二星" and app.shop[3].tooltip_text.contains("一星 0/3"),"merge removes consumed copies from shop progress")
	ck(app.refresh_button.tooltip_text.contains("一星 0/3") and app.refresh_button.tooltip_text.contains("二星：1"),"selected merge survivor uses two-star-only hint")
	ck(app.act({"type":"buy_offer","slot":3}).ok,"new spare copy can be bought after a two-star")
	ck(app.shop_cards[4].progress.text=="一星 1/3" and app.shop[4].tooltip_text.contains("二星：1"),"mixed ownership shows only spare one-star progress")
	app.select_owned(merged.unit_id)
	ck(app.refresh_button.tooltip_text.contains("一星 1/3"),"selecting a two-star uses current spare copy count")
	ck(app.act({"type":"sell_unit","unit_id":merged.unit_id}).ok,"selected two-star sells normally")
	ck(app.refresh_button.tooltip_text.contains("不保证出现任何指定角色"),"selling selected unit clears the target hint")
	ck(app.shop_cards[4].progress.text=="一星 1/3" and app.shop[4].tooltip_text.contains("二星：0"),"sale updates ownership without counting vanished two-star")
	app.select_owned(p.bench[0]);p.gold=2;app._refresh_ui()
	ck(not app.refresh_button.disabled,"informational four-gold budget never disables a legal two-gold refresh")
	ck(app.act({"type":"refresh_shop"}).ok and p.gold==0,"normal-price refresh succeeds below hinted total budget")
	p.gold=2;app.session.rules._state.config.refresh_cost=3;app._refresh_ui()
	ck(app.refresh_button.text=="刷新  ·  3 金币" and app.refresh_button.disabled,"button uses actual runtime refresh cost")
	p.gold=3;app._refresh_ui()
	ck(not app.refresh_button.disabled and app.refresh_button.tooltip_text.contains("刷新 3 + 再购买 1 张 2 = 5 金币"),"configured refresh cost also drives selected target budget")
	ck(app.act({"type":"refresh_shop"}).ok and p.gold==0,"configured-price refresh still follows match rules")
	p.gold=100;offer(app,0);app.portrait_cache["res://assets/ui/portraits/shiroko.png"]=null;app._refresh_ui()
	ck(not app.shop_cards[0].progress.visible and app.shop[0].text.contains("一星 1/3") and app.shop[0].text.contains("2 金币"),"missing portrait fallback retains price and progress without an overlapping label")
	app.select_owned("stale")
	ck(app.selected_owned.is_empty() and app.refresh_button.tooltip_text.contains("不保证出现任何指定角色"),"stale selection uses generic hint")
	before=app.session.rules.snapshot()
	ck(not app.session.command({"type":"cast_ex"}).ok and app.session.rules.snapshot()==before,"manual EX remains prohibited and cannot mutate match state")
	ck(app.shop_odds_label.text.contains("2费 44%"),"current level-weighted odds remain unchanged")
	app.free();finish()
func finish()->void:
	print("RECRUITMENT UI ",checks," checks; ",failures," failures");quit(1 if failures else 0)
