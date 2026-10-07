extends SceneTree
const Player=preload("res://vfx/native_effect_player.gd")
const RESOURCE_ROOT="res://data/effects/asuna"
var checks:=0
var failed:=0
var data:Dictionary
var prefab:Dictionary
var node:Dictionary
var components:Dictionary
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failed+=1;printerr("FAIL: "+label)
func _initialize():call_deferred("run")
func run():
 data=JSON.parse_string(FileAccess.get_file_as_string("res://data/effects/asuna/asuna/visual-templates.json"))
 for f in data.prefabs:
  if f.name=="FX_Public_AR_Motion_Shot_Asuna":prefab=f.duplicate(true)
 for n in prefab.nodes:
  if n.hierarchy.ends_with("/Muzzle_Line"):node=n
 for c in node.components:components[c.type]=c
 # Single actual source layer, unchanged parameters; read source PNG directly.
 prefab.nodes=[node]
 var production:Dictionary=data.duplicate(true);production.erase("fixtureOnly")
 production.renderAdaptations={"asunaMuzzleLineVelocityOrientation":true}
 var check_player=Player.new();root.add_child(check_player)
 ck(check_player._is_asuna_muzzle_line(production,prefab,node,components),"explicit production metadata eligible")
 check_player.free()
 ck(spawned_candidate(production,false),"production metadata activates with legacy private flag OFF")
 ck(not spawned_candidate(data,false),"private fixture remains opt-in")
 ck(spawned_candidate(data,true),"private fixture existing opt-in retained")
 var private_tagged:Dictionary=data.duplicate(true);private_tagged.renderAdaptations=production.renderAdaptations
 ck(not spawned_candidate(private_tagged,false),"production field cannot bypass private fixture opt-in")
 ck(spawned_candidate(private_tagged,true),"tagged private fixture with opt-in accepted")
 var unflagged:Dictionary=production.duplicate(true);unflagged.erase("renderAdaptations")
 ck(not spawned_candidate(unflagged,false),"unflagged production unchanged")
 ck(not spawned_candidate(unflagged,true),"legacy private switch cannot enable unflagged production")
 for bad in [null,false,0,1,"true",[],{"asunaMuzzleLineVelocityOrientation":false},{"asunaMuzzleLineVelocityOrientation":1},{"asunaMuzzleLineVelocityOrientation":"true"},{"asunaMuzzleLineVelocityOrientation":null}]:
  var altered:Dictionary=production.duplicate(true);altered.renderAdaptations=bad
  ck(not spawned_candidate(altered,false),"malformed/non-boolean metadata fails closed")
 var roster:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/effects/battle-events-compact.json")).activeRoster
 roster=roster.filter(func(character):return character!="asuna")
 for character in roster:
  var altered:Dictionary=production.duplicate(true);altered.character=character
  ck(not spawned_candidate(altered,false),"other active character excluded even when tagged: "+character)
 for bad_fixture in [null,1,"true",[],{}]:
  var malformed:Dictionary=production.duplicate(true);malformed.fixtureOnly=bad_fixture
  ck(not spawned_candidate(malformed,true),"malformed fixture boundary fails closed even with legacy switch")
 var check_identity=Player.new();root.add_child(check_identity)
 for kind in ["ParticleSystem","ParticleSystemRenderer"]:
  var altered:Dictionary=components.duplicate(true);altered[kind].source.rawSha256="wrong"
  ck(not check_identity._is_asuna_muzzle_line(production,prefab,node,altered),"exact "+kind+" receipt required")
 var wrong:Dictionary=node.duplicate();wrong.hierarchy+="_Other"
 ck(not check_identity._is_asuna_muzzle_line(production,prefab,wrong,components),"exact source path required")
 check_identity.free()
 var before_data:String=JSON.stringify(production)
 var enabled_frame:Dictionary=frame_result(production)
 var legacy_frame:Dictionary=frame_result(unflagged)
 ck(enabled_frame.calls>0,"production-selected particles consume camera callback")
 ck(legacy_frame.calls==0,"unflagged particles do not consume camera callback")
 ck(enabled_frame.centers==legacy_frame.centers,"metadata activation preserves particle centers")
 ck(enabled_frame.dimensions==legacy_frame.dimensions,"metadata activation preserves particle dimensions")
 ck(enabled_frame.lives==legacy_frame.lives,"metadata activation preserves schedules/speeds/lifetimes")
 ck(JSON.stringify(production)==before_data,"production source dictionary remains unmodified")
 print("ACTIVATION checks=",checks," failures=",failed);quit(1 if failed else 0)
func spawned_candidate(source:Dictionary,private_opt_in:bool)->bool:
 var player=Player.new();root.add_child(player)
 player.asuna_stretch_orientation_candidate=private_opt_in
 var event:Dictionary={"start":0.0,"duration":1.5,"speed":1.0,"clipIn":0.0,"particleRandomSeed":9751}
 player._spawn_event(1,source,prefab,RESOURCE_ROOT,event,0.0,func(_binding,_event,_at):return Transform3D.IDENTITY)
 if player._effects.size()!=1 or player._effects[0].layers.size()!=1:
  printerr("FIXTURE ERROR: selected source layer did not spawn ",player._issues);failed+=1;player.free();return false
 var result:bool=player._effects[0].layers[0].get("stretch_candidate",false)
 player.free();return result

func frame_result(source:Dictionary)->Dictionary:
 var player=Player.new();root.add_child(player)
 var callback_calls:Array=[0]
 player.stretch_camera_at=func(at:float):
  callback_calls[0]+=1
  return {"time":at,"projection":"orthographic","transform":Transform3D(Basis.IDENTITY,Vector3(0,0,10))}
 var event:Dictionary={"start":0.0,"duration":1.5,"speed":1.0,"clipIn":0.0,"particleRandomSeed":9751}
 player._spawn_event(1,source,prefab,RESOURCE_ROOT,event,0.0,func(_binding,_event,_at):return Transform3D.IDENTITY)
 player.update_time(0.95)
 var centers:Array=[];var dimensions:Array=[];var lives:Array=[]
 for layer in player._effects[0].layers:
  for item in layer.particles:
   lives.append([item.birth,item.life,item.sample.start_speed])
   if item.node.visible:
    centers.append(item.node.global_position)
    # Axes are stored as floats; compare dimension lengths with rounded micro-units.
    var size:Vector3=item.node.global_transform.basis.get_scale().abs()
    dimensions.append(Vector3(roundf(size.x*100000),roundf(size.y*100000),roundf(size.z*100000)))
 var result:Dictionary={"calls":callback_calls[0],"centers":centers,"dimensions":dimensions,"lives":lives}
 player.free();return result
