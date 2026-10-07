extends SceneTree
const Duel=preload('res://core/lan/duel_runtime.gd')
const Codec=preload('res://core/lan/view_codec.gd')
const Protocol=preload('res://core/lan/protocol.gd')
func _initialize():
 var d=Duel.new();var rosters:Array=[[],[]];var positions:Array=[{},{}]
 var keys:Array=['nonomi','iori','mutsuki','shiroko','yuuka']
 for team in range(2):
  for i in range(5):
   var id:String='u'+str(team)+str(i);rosters[team].append({'id':id,'character_id':keys[i],'star':2});positions[team][id]=Vector2(-4+i*2,5)
 var arena=load('res://core/tactical_maps.gd').new().get_map('open_plaza')
 var settings:Dictionary=load('res://core/battle_pacing.gd').options(3);settings.merge({'seed':31,'combat_mode':'tactical_v1','arena_half':9.0,'tactical_ai_teams':[0,1]})
 assert(d.configure({'id':'dense','left_id':'p0','right_id':'p1','generation':1,'positions':positions},rosters,arena,settings).ok);d.start()
 var authority=load('res://core/lan/authority.gd').new();authority.start_match(31)
 var player:Dictionary=authority.rules._player_ref('p0');player.level=5;player.units.clear();player.bench.clear();player.deployed.clear()
 for i in range(14):
  var owned:Dictionary={'id':'u'+str(i),'character_id':keys[i%5],'star':2,'base_enabled':true,'passive_enabled':true,'ex_enabled':true};player.units.append(owned)
  if i<5:player.deployed.append(owned.id)
  else:player.bench.append(owned.id)
 var max_bytes:=0;var max_telegraphs:=0;var cursor:=0
 while d.result().is_empty():
  d.advance(0.1)
  var view:Dictionary=authority.view_for('p0');view.battle=d.snapshot();view.events=d.events_since(cursor)
  view.names={}
  for i in range(8):view.names['p'+str(i)]='最长允许二十四字昵称最长允许二十四字昵称测试名字'
  view.last_result={'round':5,'duels':[],'income_by_player':{},'standings':view.standings}
  for i in range(4):view.last_result.duels.append({'left_id':'p'+str(i*2),'right_id':'p'+str(i*2+1),'winner':'draw','left_remaining':5,'right_remaining':5,'duration_ticks':1800,'finish_reason':'timeout','remaining_hp_totals':[50000,50000],'max_hp_totals':[150000,150000]})
  if not view.events.is_empty():cursor=view.events[-1].wire_sequence
  max_telegraphs=maxi(max_telegraphs,view.battle.telegraphs.size())
  var encoded:PackedByteArray=Protocol.encode({'protocol':1,'type':'view','epoch':1,'seq':cursor,'payload':Codec.pack(view)})
  assert(not encoded.is_empty());max_bytes=maxi(max_bytes,encoded.size())
 assert(max_telegraphs>0 and max_bytes<60000)
 print('LAN_DENSE_PACKETS PASS bytes=',max_bytes,' telegraphs=',max_telegraphs,' tick=',d.clock.sim.tick);d.close();authority.close();quit()
