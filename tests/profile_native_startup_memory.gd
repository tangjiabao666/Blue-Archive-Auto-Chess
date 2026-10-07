extends SceneTree
## Diagnostic only. Records allocator/RSS by real native loading phase; no source mutations.
const Source=preload("res://vfx/native_source.gd")
const UnitView=preload("res://scripts/unit_view.gd")
const Sim=preload("res://core/character_sim.gd")
const Player=preload("res://vfx/native_effect_player.gd")
const EVENTS="res://data/effects/battle-events-compact.json"
const ROSTER=["shiroko","hoshino","hina","aru","yuuka","aris","iori","tsubaki","nonomi","mutsuki","haruna","koharu"]
var holds:Array=[]
var rows:Array=[]
var started:int
func _initialize()->void:call_deferred("run")
func mark(phase:String)->void:
 var rss:int=-1
 for line in FileAccess.get_file_as_string("/proc/self/status").split("\n"):
  if line.begins_with("VmRSS:"):rss=int(line.trim_prefix("VmRSS:").strip_edges().split(" ",false)[0])*1024
 var row={"phase":phase,"static_bytes":OS.get_static_memory_usage(),"peak_bytes":OS.get_static_memory_peak_usage(),"rss_bytes":rss,"ms":Time.get_ticks_msec()-started,"json_cached":Source.json_cache.size(),"animation_libraries":UnitView._native_libraries.size()}
 rows.append(row);print("MEMORY "+JSON.stringify(row))
func run()->void:
 started=Time.get_ticks_msec()
 var args=OS.get_cmdline_user_args()
 var mode:String=args[0] if not args.is_empty() else "json"
 var characters:Array=ROSTER.duplicate()
 if args.size()>1:characters=[args[1]]
 mark("baseline")
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 var simulation=Sim.new()
 if mode in ["json","json-release"]:
  for character in characters:
   var path:String="res://data/effects/"+character+"/visual-templates.json"
   var data:Dictionary=Source.read_json(path)
   mark("parsed:"+character)
   data={}
   if mode=="json-release":Source.json_cache.clear();mark("released:"+character)
  Source.json_cache.clear();mark("cache_cleared")
 elif mode=="model":
  for character in characters:
   var packed:PackedScene=load(profiles[character].model_path)
   holds.append(packed);mark("packed:"+character)
   var instance=packed.instantiate();root.add_child(instance);holds.append(instance);mark("instance:"+character)
 elif mode in ["view","combined"]:
  var views:Dictionary={};var units:Array=[]
  for character in characters:
   var unit:Dictionary=simulation.preview_unit(character,2,units.size(),0)
   unit.presentation=profiles[character];units.append(unit)
   var view=UnitView.new();root.add_child(view);view.setup(unit,{},1);views[unit.id]=view
   mark("view:"+character)
  if mode=="combined":
   var vfx=load("res://scripts/native_combat_vfx.gd").new();root.add_child(vfx);vfx.configure(profiles);mark("vfx_configured")
   vfx.begin_roster(views,units,1);mark("vfx_begin_roster")
   vfx.free();mark("vfx_freed")
  for view in views.values():view.free()
  mark("views_freed")
  UnitView._native_libraries.clear();mark("libraries_cleared")
 elif mode=="warmup":
  var player=Player.new();root.add_child(player)
  for character in characters:
   Source.read_json("res://data/effects/"+character+"/visual-templates.json");mark("parsed:"+character)
   for kind in ["ex","basic"]:
    player.warmup_timeline(EVENTS,character,kind);mark("warm:"+character+":"+kind)
   await process_frame
   mark("warm_settled:"+character)
  player.free();mark("player_freed")
  Source.json_cache.clear();mark("cache_cleared")
 for item in holds:
  if item is Node and is_instance_valid(item):item.free()
 holds.clear()
 await process_frame
 mark("end")
 var output:=FileAccess.open("res://evidence/memory-profile-"+mode+("-"+str(args[1]) if args.size()>1 else "")+".json",FileAccess.WRITE)
 output.store_string(JSON.stringify(rows,"  "))
 quit()
