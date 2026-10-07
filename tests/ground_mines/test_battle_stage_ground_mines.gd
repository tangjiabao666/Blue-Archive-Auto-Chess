extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const Stage=preload("res://scripts/battle_stage.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func placed(id:int,tick:int=10,expiry:int=40,generation:int=7)->Dictionary:
 return {"type":"mine_placed","event_id":"placed:%s"%id,"generation":generation,"tick":tick,"actor_id":0,"mine_id":id,"cell":Vector2(2,3),"expires_tick":expiry}
func presenter(stage:Node3D):
 for child in stage.get_children():
  if child.get_script()!=null and child.get_script().resource_path=="res://scripts/native_ground_mines.gd":return child
 return null
func run()->void:
 var stage=Stage.new();root.add_child(stage)
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 profiles.mutsuki.model_scale=1.95
 stage.configure(profiles,[])
 var mines=presenter(stage)
 ck(mines!=null,"battle stage owns native ground mine presenter")
 if mines==null:stage.free();finish();return
 var sim=Sim.new()
 var roster:Array=[sim.preview_unit("mutsuki",1,0,0,Vector2(0,2)),sim.preview_unit("yuuka",2,1,1,Vector2(0,-4))]
 stage.set_roster(roster,7,false)
 ck(mines.diagnostics().generation==7,"battle roster initializes mine generation")
 ck(stage.native_vfx.diagnostics().generation==7 and stage.native_props.diagnostics().generation==7,"existing VFX and skill props keep battle lifecycle")
 var events:Array=[placed(1),placed(1),placed(2,10,40,6)]
 var untagged:Dictionary=placed(3);untagged.erase("generation");events.append(untagged)
 var original:Array=events.duplicate(true)
 var original_units:Array=roster.duplicate(true)
 stage.update_display(roster,events,0.45)
 ck(mines.diagnostics().active_mines==0 and mines.diagnostics().queued_events==1,"stage forwards only current generation deduplicated placement")
 ck(mines.diagnostics().stale_events==0 and mines.diagnostics().duplicate_events==0,"stale and duplicate events are filtered before mine consume")
 ck(events==original and roster==original_units,"stage mine dispatch preserves authoritative inputs")
 stage.update_display(roster,[],0.5)
 ck(mines.diagnostics().active_mines==1 and mines.diagnostics().time==0.5,"empty event frame advances mine clock and spawns due placement")
 var state:Dictionary=mines.snapshot()
 if state.has(1):
  ck(state[1].cell==Vector2(2,3) and state[1].team==0,"stage passes authoritative placement and owner roster")
  ck(state[1].bounds.size.x>0.45 and state[1].bounds.size.x<0.51,"stage configures mine scale from character profiles")
 ck(stage.native_vfx.diagnostics().time==0.5 and stage.native_props.diagnostics().time==0.5,"other VFX still advance on every display update")
 roster[1].shield=420;roster[1].shield_until=100
 stage.update_display(roster,[placed(1)],0.5)
 ck(mines.snapshot()==state and mines.diagnostics().spawned==1,"paused update and repeated stage event preserve native mine pose")
 ck(stage.bars[1].status.tooltip_text.contains("420"),"status HUD still follows shield while mines are active")
 ck(is_equal_approx(stage.bars[1].status.status.ex.remaining_seconds,maxi(0,roster[1].skill_ready-10)*0.05),"status HUD cooldown uses same display clock")
 var trigger:Dictionary={"type":"mine_triggered","event_id":"trigger:1","generation":7,"tick":15,"actor_id":0,"mine_id":1}
 stage.update_display(roster,[trigger],0.7)
 ck(mines.diagnostics().active_mines==1,"stage does not apply future trigger early")
 stage.update_display(roster,[],0.75)
 ck(mines.get_child_count()==0,"stage clock removes triggered mine on its authoritative tick")
 stage.update_display(roster,[placed(4,15,20)],0.75)
 stage.update_display(roster,[],1.0)
 ck(mines.get_child_count()==0,"empty frame expires mine at declared lifetime")
 stage.update_display(roster,[placed(5,20,80),placed(6,60,80)],1.0)
 ck(mines.diagnostics().active_mines==1 and mines.diagnostics().queued_events==1,"reset fixture has both live and future mines")
 stage.set_roster(roster,7,false)
 ck(mines.get_child_count()==0 and mines.diagnostics().queued_events==0 and mines.diagnostics().time==0.0,"same-generation roster replay resets all mine state immediately")
 stage.update_display(roster,[placed(5,0,80)],0.0)
 ck(mines.diagnostics().active_mines==1,"same-generation reset permits replayed mine identity")
 stage.set_roster(roster,8,true)
 ck(mines.get_child_count()==0 and mines.diagnostics().generation==8,"preparation roster clears mines and advances generation")
 ck(stage.native_vfx.diagnostics().generation==8 and stage.native_props.diagnostics().generation==8,"preparation still resets other VFX")
 ck(stage.bars[1].status.status.ex.kind=="preparation","preparation keeps status HUD in its existing preparation mode")
 stage.set_roster(roster,9,false)
 stage.update_display(roster,[placed(5,0,80,7),placed(5,0,80,9)],0.0)
 ck(mines.diagnostics().active_mines==1 and mines.diagnostics().stale_events==0,"new battle rejects old generation before dedup and permits reused event ID")
 stage.update_display(roster,[{"type":"death","event_id":"death:0","generation":9,"tick":1,"actor_id":0}],0.05)
 ck(mines.get_child_count()==0,"stage forwards owner death to mine cleanup")
 stage.set_roster(roster,10,false)
 stage.update_display(roster,[placed(7,0,80,10),placed(8,40,80,10)],0.0)
 stage.update_display(roster,[{"type":"finished","event_id":"finished","generation":10,"tick":1}],0.05)
 ck(mines.get_child_count()==0 and mines.diagnostics().finished and mines.diagnostics().queued_events==0,"stage forwards finish and clears live and future mines")
 stage.set_roster(roster,11,false)
 var missing_generation:Dictionary=placed(9,0,80,11);missing_generation.erase("generation")
 stage.update_display(roster,[missing_generation],0.0)
 stage.update_display(roster,[placed(9,0,80,11)],0.0)
 ck(mines.diagnostics().active_mines==1,"untagged event cannot poison stage dedup for later generation-validated event")
 stage.set_roster(roster,12,false)
 stage.update_display(roster,[placed(10,0,80,12)],0.0)
 var missing_death:Dictionary={"type":"death","event_id":"death:legacy","tick":1,"actor_id":0}
 stage.update_display(roster,[missing_death],0.05)
 ck(stage.dead_at.has(0) and mines.diagnostics().active_mines==1,"legacy untagged death remains accepted by other stage consumers but not mines")
 var valid_death:Dictionary=missing_death.duplicate();valid_death.generation=12
 stage.update_display(roster,[valid_death],0.05)
 ck(mines.get_child_count()==0,"legacy untagged death cannot poison authoritative mine cleanup event")
 stage.set_roster(roster,13,false)
 stage.update_display(roster,[placed(11,0,80,13)],0.0)
 var missing_finish:Dictionary={"type":"finished","event_id":"finished:legacy","tick":1}
 stage.update_display(roster,[missing_finish],0.05)
 ck(mines.diagnostics().active_mines==1,"untagged finish cannot end authoritative mine presentation")
 var valid_finish:Dictionary=missing_finish.duplicate();valid_finish.generation=13
 stage.update_display(roster,[valid_finish],0.05)
 ck(mines.get_child_count()==0 and mines.diagnostics().finished,"legacy untagged finish cannot poison authoritative mine cleanup event")
 ck(mines.diagnostics().issues.is_empty(),"stage-integrated mine lifecycle reports no resource or timing issues")
 stage.free();finish()
func finish()->void:
 print("BATTLE_STAGE_GROUND_MINES ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
