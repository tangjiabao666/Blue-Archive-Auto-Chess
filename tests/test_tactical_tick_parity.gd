extends SceneTree
const Clock=preload('res://core/character_clock.gd')
func make_clock():
 var c=Clock.new();c.use_combat_mode('tactical_v1');c.generation=7
 var roster:Array=[{'id':10,'team':0,'cell':Vector2(0,2),'character_id':'yuuka','star':2},{'id':20,'team':1,'cell':Vector2(0,-2),'character_id':'serika','star':2}]
 assert(c.sim.configure(roster,{'seed':17,'tactical_ai_teams':[1]}).is_empty());c.sim.start()
 assert(c.sim.queue_tactical_command({'generation':7,'team':0,'sequence':1,'tick':1,'type':'cast_ex','actor_id':10,'target_id':10,'point':Vector2(0,2)}).ok)
 return c
func _initialize()->void:
 var a=make_clock();var b=make_clock();var left:Array=[];var right:Array=[]
 for i in range(60):left.append_array(a.advance(0.05))
 for i in range(10):right.append_array(b.advance(0.3))
 var good:bool=left==right and a.sim.snapshot()==b.sim.snapshot() and a.generation==b.generation
 print('TACTICAL_TICK_PARITY ', 'PASS' if good else 'FAIL',' events=',left.size(),' tick=',a.sim.tick)
 quit(0 if good else 1)
