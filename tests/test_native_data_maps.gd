extends SceneTree
## These RGBA channels encode parameters, not transparent color edges.
const SLOTS=["_HairSpecTex","_MaskTex","_SourceTex"]
var checks:=0
var failures:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize():
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"));var paths:Dictionary={};var characters:Dictionary={}
 for key in profiles:
  for material in profiles[key].get("materials",[]):
   for slot in SLOTS:
    var path:String=material.get("textures",{}).get(slot,"")
    if not path.is_empty():paths[path]=true;characters[key]=true
 ck(characters.size()==profiles.size(),"data-map coverage includes every active source profile")
 for path in paths:
  var config=ConfigFile.new();ck(config.load(path+".import")==OK,"readable import "+path)
  ck(config.get_value("params","process/fix_alpha_border",true)==false,"data RGB must not be altered using parameter alpha "+path)
  var source=Image.load_from_file(ProjectSettings.globalize_path(path));var texture:Texture2D=load(path);var imported=texture.get_image()
  ck(source!=null and imported!=null,"source/import image available "+path)
  if source==null or imported==null:continue
  if imported.is_compressed():imported.decompress()
  source.convert(Image.FORMAT_RGBA8);imported.convert(Image.FORMAT_RGBA8)
  ck(source.get_size()==imported.get_size() and source.get_data()==imported.get_data(),"all imported RGBA parameter bytes equal source "+path)
 print("NATIVE DATA MAPS profiles=",characters.size()," maps=",paths.size()," checks=",checks," FAILURES=",failures);quit(1 if failures else 0)
