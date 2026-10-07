extends SceneTree
const Duel=preload('res://core/offscreen_duel.gd')
const Wire=preload('res://core/offscreen_process_worker.gd')
const League=preload('res://core/tactical_league.gd')
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 var input:Dictionary={'left_id':'p1','right_id':'p2','seed':23,'left_army':[{'character_id':'yuuka','star':1}],'right_army':[{'character_id':'serika','star':1}],'settings':{'combat_mode':'tactical_v1','max_ticks':2,'timeout_total_hp':true},'arena_config':{}}
 var duel=Duel.new();ck(duel.configure(input.left_army,input.right_army,'p1','p2',23,input.settings).is_empty(),'new offscreen policy configures');duel.run()
 var result:Dictionary=duel.result
 ck(result.outcome.has('remaining_hp_totals'),'NPC outcome includes HP witness')
 if failures:finish();return
 ck(result.outcome.winner!='draw','unequal remaining HP produces NPC winner')
 ck(Wire.validate_results([result],[input]).is_empty(),'worker accepts verified living-loser timeout')
 var bad:Dictionary=result.duplicate(true);bad.outcome.winner='draw';ck(not Wire.validate_results([bad],[input]).is_empty(),'worker rejects inconsistent HP winner')
 var league=League.new();ck(league.get_property_list().any(func(p):return p.name=='hp_timeout'),'league has explicit HP rule version')
 if failures:finish();return
 league.hp_timeout=true;var rows:Array=[]
 for i in range(0,8,2):
  for side in range(2):rows.append({'participant_id':'p'+str(i+side),'opponent_id':'p'+str(i+1-side),'result':'win' if side==0 else 'loss','remaining_hp_ratio':0.025 if side==0 else 0.5,'remaining_hp_total':1000 if side==0 else 500,'maximum_hp_total':40000 if side==0 else 1000,'duration_ticks':1800,'finish_reason':'timeout'})
 ck(league.record_round(1,rows).ok,'raw total wins despite lower percentage')
 var restored=League.new();restored.hp_timeout=true;ck(restored.restore(JSON.parse_string(JSON.stringify(league.snapshot()))).ok,'HP witness ledger roundtrips')
 var tampered:Dictionary=league.snapshot();tampered.rounds[0].outcomes[0].remaining_hp_total=1;ck(not restored.restore(tampered).ok,'inconsistent saved health/result rejected')
 var legacy=League.new();ck(not legacy.restore(league.snapshot()).ok,'old profile rejects new ledger')
 finish()
func finish():print('SHORT_ROUND_OUTCOMES checks=',checks,' failures=',failures);quit(1 if failures else 0)
