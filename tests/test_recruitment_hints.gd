extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:
	var path:="res://core/recruitment_hints.gd"
	ck(ResourceLoader.exists(path),"pure recruitment hints helper exists")
	if not ResourceLoader.exists(path):finish();return
	var hints=load(path)
	var player:Dictionary={"units":[],"bench":[],"deployed":[]}
	ck(hints.copy_counts(player,"shiroko")=={"one_star":0,"two_star":0},"unowned character starts at zero")
	ck(hints.card_hint(player,"shiroko","白子").label=="一星 0/3","unowned card states zero progress")
	player.units=[{"id":"a","character_id":"shiroko","star":1}];player.bench=["a"]
	ck(hints.card_hint(player,"shiroko","白子").label=="一星 1/3","one bench copy shows one of three")
	player.units.append({"id":"b","character_id":"shiroko","star":1});player.deployed=["b"]
	ck(hints.copy_counts(player,"shiroko").one_star==2,"bench and deployed copies both count")
	ck(hints.card_hint(player,"shiroko","白子").label=="一星 2/3","matching pair shows two of three")
	player.units.append({"id":"other","character_id":"yuuka","star":1});player.bench.append("other")
	player.units.append({"id":"unlocated","character_id":"shiroko","star":1})
	ck(hints.copy_counts(player,"shiroko").one_star==2,"other characters and unlocated records do not count")
	player.bench.append("b");player.bench.append("missing")
	ck(hints.copy_counts(player,"shiroko").one_star==2,"location overlap never double counts a copy")
	player.units[0].star=2;player.units[1].star=2
	var card:Dictionary=hints.card_hint(player,"shiroko","白子")
	ck(card.label=="仅二星","two-stars alone are distinguished from spare one-stars")
	ck(card.tooltip.contains("一星 0/3") and card.tooltip.contains("二星：2"),"two-star-only tooltip states zero progress and separate ownership")
	player.units[1].star=1
	card=hints.card_hint(player,"shiroko","白子")
	ck(card.label=="一星 1/3" and card.tooltip.contains("二星：1"),"mixed stars keep separate counts")
	ck(card.tooltip.contains("二星不计入一星进度"),"tooltip explains that two-stars cannot be spent as spare one-stars")
	var catalog:Array=[{"id":"shiroko","name":"白子","cost":2},{"id":"yuuka","name":"优香","cost":4}]
	var config:Dictionary={"refresh_cost":2}
	var before_player:Dictionary=player.duplicate(true);var before_catalog:Array=catalog.duplicate(true);var before_config:Dictionary=config.duplicate(true)
	var hint:String=hints.refresh_hint(player,catalog,config,"b")
	ck(hint.contains("白子") and hint.contains("一星 1/3"),"selected unit resolves its character and current progress")
	ck(hint.contains("刷新 2 + 再购买 1 张 2 = 4 金币"),"refresh hint includes exactly one next-copy cost")
	ck(hint.contains("刷新可能没有白子") and hint.contains("不保证合成"),"selected hint explicitly warns about randomness and no guaranteed upgrade")
	ck(hints.refresh_hint(player,catalog,config,"a").contains("一星 1/3"),"selecting a two-star still reports only its spare one-star copies")
	player.units[1].star=2
	ck(hints.refresh_hint(player,catalog,config,"a").contains("一星 0/3"),"two-star-only selection never implies a spare pair")
	player.units[1].star=1
	for id in ["","stale","unlocated"]:
		hint=hints.refresh_hint(player,catalog,config,id)
		ck(hint.contains("刷新 2 金币") and hint.contains("不保证出现任何指定角色") and not hint.contains("= 4"),"missing or invalid selection gets generic uncertainty, not a made-up target")
	hint=hints.refresh_hint(player,[],config,"b")
	ck(hint.contains("不保证出现任何指定角色") and not hint.contains("= 4"),"unknown catalog target cannot receive a fabricated price")
	catalog[0].cost=7;config.refresh_cost=3
	hint=hints.refresh_hint(player,catalog,config,"b")
	ck(hint.contains("刷新 3 + 再购买 1 张 7 = 10 金币"),"nondefault prices come from the actual catalog and config")
	hint=hints.refresh_hint(player,catalog,config,"other")
	ck(hint.contains("优香") and hint.contains("刷新 3 + 再购买 1 张 4 = 7 金币"),"selection changes recompute the specific target price")
	catalog=before_catalog.duplicate(true);config=before_config.duplicate(true)
	for _iteration in range(3):
		hints.card_hint(player,"shiroko","白子");hints.refresh_hint(player,catalog,config,"b")
	ck(player==before_player and catalog==before_catalog and config==before_config,"repeated hints leave every input unchanged")
	finish()
func finish()->void:
	print("RECRUITMENT HINTS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
