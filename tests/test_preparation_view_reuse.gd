extends SceneTree
## Real native actor/HUD identity and lifecycle coverage; no UnitView doubles.
const Stage=preload("res://scripts/battle_stage.gd")
const Sim=preload("res://core/character_sim.gd")
var checks:=0
var failures:=0
var selection_events:=0
var placement_events:=0
var sim=Sim.new()
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func unit(character:String,id:int,team:int=0,star:int=1)->Dictionary:
	var value:Dictionary=sim.preview_unit(character,star,id,team,Vector2(id,3 if team==0 else -3))
	value.roster_unit_id="owned:%s:%s"%[team,id]
	return value
func identity(stage:Node3D)->Dictionary:
	var result:Dictionary={}
	for id in stage.views:result[id]=[stage.views[id].get_instance_id(),stage.bars[id].root.get_instance_id(),stage.views[id]._model.get_instance_id(),stage.views[id].player.get_instance_id()]
	return result
func same(stage:Node3D,before:Dictionary,id:int,label:String)->void:
	ck(identity(stage)[id]==before[id],label)
func replaced(stage:Node3D,before:Dictionary,id:int,label:String)->void:
	ck(identity(stage)[id][0]!=before[id][0] and identity(stage)[id][1]!=before[id][1],label)
func bone_poses(view:Node3D)->Array:
	var result:Array=[]
	for skeleton in view._model.find_children("*","Skeleton3D",true,false):
		for index in skeleton.get_bone_count():result.append(skeleton.get_bone_pose(index))
	return result
func run()->void:
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	var stage=Stage.new();root.add_child(stage);stage.configure(profiles,[])
	stage.selected.connect(func(_id):selection_events+=1)
	stage.placement_requested.connect(func(_id,_point):placement_events+=1)
	var roster:Array=[unit("yuuka",0),unit("shiroko",7,1)]
	stage.set_roster(roster,20,true)
	var before:Dictionary=identity(stage)
	var original_pose:Array=bone_poses(stage.views[0])
	stage.set_selected(0)
	stage.update_display(roster,[],1.75,0)
	var addition:Dictionary=unit("hoshino",1)
	roster.append(addition)
	var original:Array=roster.duplicate(true)
	stage.set_roster(roster,20,true)
	same(stage,before,0,"adding own unit preserves own actor, model, animation player and HUD")
	same(stage,before,7,"adding own unit preserves scouted enemy actor and HUD")
	ck(stage.views.size()==3 and stage.bars.size()==3,"addition creates exactly one actor and HUD")
	ck(roster==original and stage.units==roster,"roster refresh does not mutate caller data")
	ck(stage.selected_id==-1 and not stage.views[0].get_node("AttackRangeIndicator").visible,"roster refresh clears previous selection")
	ck(stage.views[0]._last_time==0.0 and stage.views[0]._clip_elapsed==0.0 and is_zero_approx(stage.views[0].player.current_animation_position),"reused idle animation rewinds to the same preparation origin")
	var rewound_pose:Array=bone_poses(stage.views[0])
	var same_pose:bool=original_pose.size()==rewound_pose.size()
	for index in original_pose.size():same_pose=same_pose and original_pose[index].is_equal_approx(rewound_pose[index])
	ck(same_pose,"reused native skeleton returns to original preparation pose")
	stage.update_display(roster,[],0.25,0)
	ck(is_equal_approx(stage.views[0].player.current_animation_position,0.25) and stage.views[0]._clip_elapsed==0.25,"reused native animation advances correctly after rewind")
	stage.set_selected(1)
	ck(stage.views[1].get_node("AttackRangeIndicator").visible and not stage.views[7].get_node("AttackRangeIndicator").visible,"selection still updates correct own and enemy actors")
	before=identity(stage)
	roster.reverse()
	stage.set_roster(roster,20,true)
	for id in before:same(stage,before,id,"array reorder preserves stable actor ID %s"%id)
	before=identity(stage)
	var removed_view=stage.views[1];var removed_hud=stage.bars[1].root
	roster.erase(addition)
	stage.set_roster(roster,20,true)
	same(stage,before,0,"removal preserves unaffected own view")
	same(stage,before,7,"removal preserves unaffected enemy view")
	ck(removed_view.get_parent()==null and removed_view.is_queued_for_deletion() and removed_hud.get_parent()==null,"removed actor and HUD are detached immediately")
	ck(not stage.views.has(1) and not stage.bars.has(1),"removed IDs leave no stale dictionary entries")
	await process_frame
	ck(not is_instance_valid(removed_view) and not is_instance_valid(removed_hud),"removed actor and HUD are freed")
	before=identity(stage)
	var own:Dictionary=roster[1]
	own.cell=Vector2(-4.25,1.5);own.hp=123;own.max_hp=246;own.weapon="Updated weapon";own.damage_type="Mystic";own.armor_type="HeavyArmor"
	stage.set_roster(roster,20,true)
	same(stage,before,0,"mutable location, health and tooltip data preserve native actor and HUD")
	ck(stage.views[0].position==Vector3(-4.25,0,1.5),"reused actor follows current cell exactly")
	ck(stage.bars[0].hp.size.x==30.0 and stage.bars[0].root.visible,"reused health bar reflects current health and max health")
	ck(stage.bars[0].label.tooltip_text.contains("Updated weapon") and stage.bars[0].label.tooltip_text.contains("神秘") and stage.bars[0].label.tooltip_text.contains("重装甲"),"reused tooltip reflects updated weapon and damage/armor types")
	ck(stage.bars[0].root.position.is_equal_approx(stage.camera.unproject_position(stage.views[0].global_position+Vector3(0,1.65,0))-Vector2(30,0)),"reused HUD follows current projection")
	before=identity(stage)
	own.hp=0;stage.set_roster(roster,20,true)
	same(stage,before,0,"zero health snapshot preserves otherwise clean preparation actor")
	ck(not stage.bars[0].root.visible,"zero health hides reused HUD")
	own.hp=own.max_hp;stage.set_roster(roster,20,true)
	ck(stage.bars[0].root.visible and stage.views[0].visible,"live snapshot restores reused HUD")
	before=identity(stage)
	own.shield=321;own.shield_until=100;stage.set_roster(roster,20,true)
	ck(stage.views[0].diagnostics().shield==321,"reused actor receives current shield state")
	own.erase("shield");own.erase("shield_until");stage.set_roster(roster,20,true)
	same(stage,before,0,"optional snapshot fields do not require native actor rebuild")
	ck(stage.views[0].diagnostics().shield==0 and stage.views[0].diagnostics().shield_until_tick==0,"omitted shield fields cannot retain previous actor state")
	before=identity(stage)
	own.roster_unit_id="owned:replacement"
	stage.set_roster(roster,20,true)
	replaced(stage,before,0,"different roster ownership at the same actor ID invalidates actor")
	same(stage,before,7,"ownership replacement preserves scouted enemy")
	before=identity(stage)
	roster[1]=unit("hoshino",0)
	stage.set_roster(roster,20,true)
	replaced(stage,before,0,"same ID with different character replaces native actor and HUD")
	same(stage,before,7,"character replacement preserves enemy view")
	ck(stage.views[0]._presentation==profiles.hoshino and stage.bars[0].label.text==profiles.hoshino.display_name,"replacement uses current character profile and caption")
	before=identity(stage);roster[1]=unit("hoshino",0,0,2);stage.set_roster(roster,20,true)
	replaced(stage,before,0,"star upgrade replaces changed actor")
	ck(stage.bars[0].label.text.ends_with(" ★★"),"upgraded caption displays current stars")
	before=identity(stage);roster[1]=unit("hoshino",0,1,2);stage.set_roster(roster,20,true)
	replaced(stage,before,0,"team change replaces changed actor")
	ck(is_zero_approx(angle_difference(stage.views[0].rotation.y,PI)) and stage.bars[0].hp.color==Color("e47891"),"team change updates facing and health color")
	before=identity(stage);roster[1].range+=1.0;stage.set_roster(roster,20,true)
	replaced(stage,before,0,"setup-only range change conservatively replaces actor")
	ck(stage.views[0].get_node("AttackRangeIndicator").radius==roster[1].range,"range remains authoritative after replacement")
	before=identity(stage);roster[1].attack_ticks+=3;stage.set_roster(roster,20,true)
	replaced(stage,before,0,"setup-only attack timing change conservatively replaces actor")
	ck(stage.views[0]._recovery_seconds==roster[1].attack_ticks*0.05,"replacement uses current attack recovery")
	before=identity(stage);profiles.hoshino.model_yaw+=0.1;profiles.hoshino.display_name="Profile changed";stage.set_roster(roster,20,true)
	replaced(stage,before,0,"in-place presentation profile mutation invalidates retained actor")
	same(stage,before,7,"profile mutation preserves unrelated character")
	ck(is_zero_approx(angle_difference(stage.views[0]._model.rotation.y,profiles.hoshino.model_yaw)) and stage.bars[0].label.text=="Profile changed ★★","profile invalidation applies native transform and caption")
	before=identity(stage);profiles.hoshino.clips.idle=profiles.hoshino.clips.walk;stage.set_roster(roster,20,true)
	replaced(stage,before,0,"nested profile mutation invalidates deep setup snapshot")
	ck(stage.views[0].IDLE==StringName(profiles.hoshino.clips.walk),"nested clip override reaches the replacement actor")
	before=identity(stage)
	stage.views[7].consume({"type":"death","event_id":"direct-death","generation":20,"tick":1,"actor_id":7})
	stage.set_roster(roster,20,true)
	replaced(stage,before,7,"direct dirty actor cannot be reused even without a stage event")
	same(stage,before,0,"dirty actor fallback preserves unrelated clean actor")
	ck(not stage.views[7].is_dead and stage.views[7].visible,"dirty actor fallback restores visible live actor")
	before=identity(stage);stage.configure(profiles,[]);stage.set_roster(roster,20,true)
	replaced(stage,before,0,"configure conservatively invalidates setup snapshots")
	before=identity(stage);roster[0]=unit("hoshino",7,1);roster[1]=unit("shiroko",0,0,2);stage.set_roster(roster,20,true)
	for id in before:replaced(stage,before,id,"ID reassignment does not retain stale character %s"%id)
	before=identity(stage);stage.set_roster(roster,21,true)
	for id in before:replaced(stage,before,id,"new preparation generation fully resets actor %s"%id)
	before=identity(stage);stage.set_roster(roster,21,false)
	for id in before:replaced(stage,before,id,"preparation to battle fully resets actor %s"%id)
	ck(stage.native_vfx.diagnostics().generation==21 and stage.native_props.diagnostics().generation==21 and stage.native_mines.diagnostics().generation==21,"all presenters retain roster generation wiring")
	var death:Dictionary={"type":"death","event_id":"death:0","actor_id":0,"generation":21,"tick":1}
	var mine:Dictionary={"type":"mine_placed","event_id":"mine:1","actor_id":7,"generation":21,"tick":1,"mine_id":1,"cell":Vector2(2,2),"expires_tick":999}
	var future_mine:Dictionary=mine.duplicate();future_mine.event_id="mine:future";future_mine.mine_id=2;future_mine.tick=200
	var future_vfx:Dictionary={"type":"damage","event_id":"damage:future","actor_id":0,"target_id":7,"ability":"normal","generation":21,"tick":200}
	stage.update_display(roster,[death,mine,future_mine,future_vfx],3.5,12)
	ck(stage.native_vfx.diagnostics().queued_events==1 and stage.native_mines.diagnostics().queued_events==1,"reset fixture includes queued VFX and future mine")
	ck(stage.views[0].is_dead and not stage.views[0].visible and stage.native_mines.diagnostics().active_mines==1,"reset fixture includes dead actor and live mine")
	before=identity(stage);stage.set_roster(roster,21,true)
	for id in before:replaced(stage,before,id,"battle to preparation fully resets actor %s"%id)
	ck(stage.seen.is_empty() and stage.dead_at.is_empty() and not stage.views[0].is_dead and stage.views[0].visible,"preparation contains no stale death or event state")
	ck(stage.native_mines.diagnostics().active_mines==0 and stage.native_mines.diagnostics().queued_events==0,"preparation contains no stale live or queued mines")
	ck(stage.native_vfx.diagnostics().queued_events==0 and stage.native_vfx.diagnostics().active_handles==0 and stage.native_props.diagnostics().active_props==0 and stage.native_props.diagnostics().queued_events==0,"preparation contains no stale queued VFX or active skill props")
	ck(stage.native_vfx.diagnostics().time==0.0 and stage.native_props.diagnostics().time==0.0 and stage.native_mines.diagnostics().time==0.0,"preparation reset restores all presenter clocks")
	stage.update_display(roster,[death,mine],3.5,12)
	before=identity(stage);stage.set_roster(roster,21,true)
	for id in before:replaced(stage,before,id,"unexpected preparation events conservatively force reset %s"%id)
	ck(stage.seen.is_empty() and stage.dead_at.is_empty() and not stage.views[0].is_dead and stage.native_mines.diagnostics().active_mines==0,"same-phase reset clears contaminated death/event/mine state")
	before=identity(stage);stage.set_roster(roster,21,false);stage.set_roster(roster,21,false)
	for id in before:replaced(stage,before,id,"same generation battle replay still fully resets actor %s"%id)
	var untagged:Dictionary=mine.duplicate();untagged.erase("generation")
	stage.update_display(roster,[untagged,mine,mine],0.05,1)
	ck(stage.seen.has("21:untagged:mine:1") and stage.seen.has("21:tagged:mine:1") and stage.native_mines.diagnostics().spawned==1,"tagged and untagged identities remain separate and authoritative mine is deduplicated")
	stage.update_display(roster,[],10.0,12)
	ck(is_equal_approx(stage.bars[0].status.status.ex.remaining_seconds,maxi(0,roster[1].skill_ready-12)*0.05),"authoritative status tick remains independent of cosmetic display clock")
	ck(selection_events==0 and placement_events==0,"roster refresh emits no synthetic selection or placement commands")
	stage.free();await process_frame
	print("PREPARATION_VIEW_REUSE ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
