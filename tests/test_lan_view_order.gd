extends SceneTree
func _initialize():
 var view=load('res://core/lan/session_view.gd').new()
 var state:Dictionary={'participant_id':'p1','round':1,'revision':2,'player':{},'battle':{'battle_id':'r1-d0','generation':10,'tick':4,'left_id':'p0','right_id':'p1','units':[{'id':0,'team':0},{'id':7,'team':1}]},'events':[{'wire_sequence':1},{'wire_sequence':2}]}
 assert(view.accept(state,'p1').ok and view.drain_events().size()==2)
 assert(view.accept(state,'p1').ok and view.drain_events().is_empty())
 var stale:Dictionary=state.duplicate(true);stale.battle.tick=2;stale.events=[{'wire_sequence':3}]
 assert(not view.accept(stale,'p1').ok and view._event_sequence==2)
 stale=state.duplicate(true);stale.revision=1;assert(not view.accept(stale,'p1').ok)
 state.battle.tick=8;state.events=[{'wire_sequence':2},{'wire_sequence':3},{'wire_sequence':4}]
 assert(view.accept(state,'p1').ok and view.drain_events().size()==2)
 assert(view.owns_actor(7) and not view.owns_actor(0))
 state.battle.battle_id='r2-d1';state.round=2;state.revision=3;state.battle.tick=0;state.events=[{'wire_sequence':1}]
 assert(view.accept(state,'p1').ok and view.drain_events().size()==1)
 print('LAN_VIEW_ORDER PASS duplicate stale delayed batches and team ownership');quit()
