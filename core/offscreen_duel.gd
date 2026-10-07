extends RefCounted
## An isolated, single-use source-combat job. No nodes, live session or shared RNG.
## Main-thread-only: advance bounded whole ticks; run drains synchronously.
const Health=preload('res://core/battle_outcome.gd')
const Sim=preload("res://core/character_sim.gd")
const TacticalSim=preload("res://core/tactical_sim.gd")
const Navigation=preload("res://core/obstacle_navigation.gd")
const ArenaHooks=preload("res://core/combat_arena_hooks.gd")
const Formations=preload("res://core/opponent_formations.gd")
const RIVALS=["p1","p2","p3","p4","p5","p6","p7"]
var _tactical:=false
var _hp_timeout:=false
var _initial_health:Dictionary={}
var _configured:=false
var _started:=false
var _cancelled:=false
var _complete:=false
var _finish_reason:=""
var _result:Dictionary={}
var result:Dictionary:
 get:
  return _result.duplicate(true)
var _simulation
var _arena
var _navigation
var _roster:Array=[]
var _left_id:String
var _right_id:String
var _left_size:=0
var _right_size:=0
static func derive_seed(match_seed:int,round_number:int,left_id:String,right_id:String)->int:
 var value:int=match_seed*1000003+round_number*9176+int(left_id.hash())*31+int(right_id.hash())*131
 return ((value%2147483646)+2147483646)%2147483646+1
func configure(left_army:Array,right_army:Array,left_id:String,right_id:String,battle_seed:int,settings:Dictionary={},arena_config:Dictionary={})->String:
 if _configured or _started or _cancelled:return "job is already configured, started or cancelled"
 if left_id not in RIVALS or right_id not in RIVALS or left_id==right_id:return "invalid offscreen participants"
 if left_army.size()>6 or right_army.size()>6:return "offscreen population exceeds six"
 if settings.get("combat_mode","legacy") not in ["legacy","tactical_v1"]:return "invalid combat mode"
 var simulation=TacticalSim.new() if settings.get("combat_mode","legacy")=="tactical_v1" else Sim.new();var definitions:Dictionary={}
 var armies:Array=[left_army.duplicate(true),right_army.duplicate(true)]
 for army in armies:
  for unit in army:
   if not unit is Dictionary or not unit.get("character_id") is String:return "invalid source unit"
   var star=unit.get("star")
   if typeof(star) not in [TYPE_INT,TYPE_FLOAT] or star not in [1,2]:return "invalid source star"
   var definition:Dictionary=simulation.character_data(unit.character_id)
   if definition.is_empty():return "unknown source character"
   definitions[unit.character_id]=definition
 var options:Dictionary=settings.duplicate(true);options.seed=battle_seed
 if not options.has("arena_half"):options.arena_half=ArenaHooks.HALF_SIZE
 if typeof(options.arena_half) not in [TYPE_INT,TYPE_FLOAT]:return "invalid arena bounds"
 var obstacles:Array=arena_config.get("obstacles",ArenaHooks.OBSTACLES)
 var navigation=Navigation.new();var error:String=navigation.configure(float(options.arena_half),obstacles)
 if not error.is_empty():return error
 var hooks=ArenaHooks.new();hooks.bind(simulation,navigation,obstacles)
 var policy=Formations.new();var roster:Array=[]
 for team in range(2):
  var army:Array=armies[team]
  var cells:Array=policy.positions(army,definitions,policy.style_for(left_id if team==0 else right_id),navigation)
  for index in range(army.size()):
   roster.append({"id":team*7+index,"team":team,"character_id":army[index].character_id,"star":int(army[index].star),"cell":-cells[index] if team==0 else cells[index]})
 var validation_roster:Array=roster
 # Even empty duels must reject invalid simulator options. These sentinels are
 # never started; the actual empty-army outcome is handled by advance.
 if left_army.is_empty() or right_army.is_empty():
  validation_roster=[{"id":0,"team":0,"character_id":"shiroko","star":1,"cell":Vector2(0,4.7)},{"id":7,"team":1,"character_id":"shiroko","star":1,"cell":Vector2(0,-4.7)}]
 error=simulation.configure(validation_roster,options)
 if not error.is_empty():return error
 _left_id=left_id;_right_id=right_id;_left_size=left_army.size();_right_size=right_army.size()
 _tactical=settings.get("combat_mode","legacy")=="tactical_v1"
 _hp_timeout=_tactical and settings.get("timeout_total_hp",false)
 if _hp_timeout:
  var originals:Array=[]
  for unit in roster:originals.append(simulation.preview_unit(unit.character_id,unit.star,unit.id,unit.team,unit.cell))
  _initial_health=Health.totals(originals)
 _roster=roster;_simulation=simulation;_arena=hooks;_navigation=navigation;_configured=true
 return ""
func cancel()->void:
 if _complete:return
 _cancelled=true
 _finish({"ok":false,"error":"cancelled"})
func is_complete()->bool:
 return _complete
## Nonpositive budgets leave even an unstarted job untouched. Every positive
## budget counts complete simulator ticks, preserving RNG and event ordering.
func advance(max_steps:int=1)->bool:
 if _complete or max_steps<=0:return _complete
 if not _started:
  _started=true
  if not _configured:_finish({"ok":false,"error":"unconfigured"});return true
  if _left_size==0 or _right_size==0:
   _finish({"ok":true,"outcome":_outcome(_left_size,_right_size,0,"empty")});return true
  _simulation.start()
 var steps:=0
 while steps<max_steps and _simulation.phase=="running":
  steps+=1
  for event in _simulation.step():
   if event.type=="finished":_finish_reason=event.reason
 if _simulation.phase=="running":return false
 var alive:Array=[0,0]
 for unit in _simulation.units:
  if unit.hp>0:alive[unit.team]+=1
 _finish({"ok":true,"outcome":_outcome(alive[0],alive[1],_simulation.tick,_finish_reason)})
 return true
## Compatibility/reference API. Production sessions use bounded advance calls.
func run()->void:
 while not advance(128):pass
func _outcome(left_remaining:int,right_remaining:int,ticks:int,reason:String)->Dictionary:
 var value:Dictionary={"left_id":_left_id,"right_id":_right_id,"winner":"left" if left_remaining>0 and right_remaining==0 else "right" if right_remaining>0 and left_remaining==0 else "draw","left_remaining":left_remaining,"right_remaining":right_remaining,"duration_ticks":ticks,"finish_reason":reason}
 if _hp_timeout:
  value.merge(_initial_health.duplicate(true) if reason=="empty" else Health.totals(_simulation.units))
  value.winner=Health.winner(value.remaining_hp_totals)
 return value
func _finish(value:Dictionary,capture_health:bool=true)->void:
 if _complete:return
 if capture_health and _tactical and value.get("ok",false):
  var ratios:Array=[1.0 if _left_size>0 else 0.0,1.0 if _right_size>0 else 0.0]
  if value.outcome.finish_reason!="empty" and _simulation!=null:
   var hp:Array=[0.0,0.0];var maximum:Array=[0.0,0.0]
   for unit in _simulation.units:
    hp[unit.team]+=maxf(0.0,float(unit.hp));maximum[unit.team]+=float(unit.max_hp)
   for team in range(2):ratios[team]=clampf(hp[team]/maximum[team],0.0,1.0) if maximum[team]>0 else 0.0
  value.remaining_hp_ratios=Health.ratios(value.outcome) if _hp_timeout else ratios
 if _simulation!=null:
  _simulation.position_free=Callable();_simulation.segment_free=Callable();_simulation.line_of_sight=Callable();_simulation.path_step=Callable();_simulation.cover_query=Callable()
 _simulation=null;_arena=null;_navigation=null;_roster.clear()
 _result=value.duplicate(true);_complete=true
