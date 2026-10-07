extends SceneTree
class MockRoom extends Node:
 signal view_received(view:Dictionary)
 signal command_ack(result:Dictionary)
 var local_participant_id='p1'
 var local_view:Dictionary={}
 var is_host=false
 var last_command:Dictionary={}
 func mark_loaded():pass
 func submit_command(command):last_command=command
 func request_next():pass
func _initialize():call_deferred('run')
func run():
 var script=load('res://scripts/lan/game_client.gd');assert(script!=null)
 var a=load('res://core/lan/authority.gd').new();a.start_match(5)
 a.rules._pairs=[['p0','p1'],['p2','p3'],['p4','p5'],['p6','p7']]
 var room=MockRoom.new();root.add_child(room)
 var client=script.new();root.add_child(client);client.bind_room(room)
 client._receive(a.view_for('p1'));assert(client.header.text.contains('第 1'))
 client._preview(0);assert(client.preview_panel.visible);client.preview_panel.hide()
 for id in ['p0','p1','p2']:
  var b=a.rules.execute_for(id,{'type':'buy_offer','slot':0});a.rules.execute_for(id,{'type':'deploy_unit','unit_id':b.unit_id});a.rules.set_ready(id,true)
 a.begin_round();client._receive(a.view_for('p1'))
 for id in ['p0','p1','p2']:a.mark_loaded(id)
 a.advance(0.5)
 var state:Dictionary=a.view_for('p1');state.events=a.events_since('p1',0);client._receive(state)
 assert(client.view.state.phase=='battle' and client._visual_time==0.0)
 client._process(0.016);var first:float=client._visual_time
 client._process(0.016);var second:float=client._visual_time
 client._process(0.016);assert(first>0 and second>first and client._visual_time>second)
 assert(client._visual_time<state.battle.tick*0.05)
 assert(client.view.local_team()==1 and client.view.owns_actor(7) and not client.view.owns_actor(0))
 assert(client.stage.local_team==1 and client.stage.views[7].local_team==1)
 assert(client.stage.bars[7].hp.color==Color('3aaadc') and client.stage.bars[0].hp.color==Color('e47891'))
 assert(client.tactical_hud.visible and not client._side.visible);client._arm_slot(0);assert(client.armed_actor==7)
 client._actor_pressed(0);assert(room.last_command.type=='cast_ex' and room.last_command.actor_id==7 and client.armed_actor==-1)
 client._show_feedback('energy_or_cooldown');assert(client.tactical_hud.hint_text.text.contains('能量不足'))
 client._process(0.02);assert(client._visual_time<=state.battle.tick*0.05)
 var displayed:float=client._visual_time
 var stale:Dictionary=state.duplicate(true);stale.battle.tick=2;client._receive(stale);assert(client.view.state.battle.tick==10 and client._visual_time==displayed)
 # Presentation-only terminal fixture: Next cannot outrun final events.
 var terminal:Dictionary=state.duplicate(true);terminal.phase='result';terminal.revision+=1;terminal.battle.phase='finished';client._receive(terminal);assert(client.next_button.disabled)
 for i in range(20):client._process(0.05)
 assert(not client.next_button.disabled and client._render_events.is_empty())
 await process_frame
 client.queue_free();room.queue_free();a.close();await process_frame
 print('LAN_GAME_CLIENT PASS prep preview battle team1 HUD');quit()
