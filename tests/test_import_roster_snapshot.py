"""Isolated importer tests: no live assets or roster are changed."""
import json,pathlib,subprocess,sys,tempfile,unittest
SCRIPT=pathlib.Path(__file__).resolve().parents[1]/'tools/import_roster_snapshot.py'
class SnapshotImporterTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.base=pathlib.Path(self.temp.name);self.root=self.base/'game';self.source=self.base/'snapshot';(self.root/'data').mkdir(parents=True);self.source.mkdir()
  self.old={name:{'display_name':name,'model_path':'res://assets/characters/'+name+'/'+name+'.glb','clips':{'basic':'custom_'+name},'custom_field':{'nested':[1,'unchanged']},'required_godot_animation_fps':123} for name in ['shiroko','hoshino','hina','aru','yuuka','aris','serika']}
  self.presentation=self.root/'data/character-presentations.json';self.presentation.write_text(json.dumps(self.old,indent=2));self.before=self.presentation.read_bytes()
 def profile(self,name='nonomi',explicit_basic=True):
  directory=self.source/name;directory.mkdir();(directory/'model.glb').write_bytes(b'glTF'+(2).to_bytes(4,'little')+b'fixture');(directory/'color.png').write_bytes(b'PNG fixture');(directory/'materials').mkdir();(directory/'materials/body.json').write_text(json.dumps({'m_Name':name+'_Body','m_Shader':{'m_PathID':42},'m_SavedProperties':{'m_TexEnvs':[['_MainTex',{'m_Texture':{'m_PathID':12},'m_Scale':{'x':1,'y':1},'m_Offset':{'x':0,'y':0}}]],'m_Floats':[],'m_Colors':[]}}));(directory/'textures.json').write_text(json.dumps({'textures':[{'path_id':'12','filename':'color.png'}]}));(directory/'manifest.json').write_text(json.dumps({'animation_sampling_hz':60,'animations':[{'name':name.capitalize()+'_Original_Public01'}],'limitations':['fixture']}))
  clips={'idle':name+'_Idle','move':name+'_Move','attack':name+'_Attack','ex':name+'_Exs'}
  if explicit_basic:clips['basic']=name+'_ExplicitBasic'
  p={'id':name,'model':str(directory/'model.glb'),'texture_manifest':str(directory/'textures.json'),'material_folder':str(directory/'materials'),'source_manifest':str(directory/'manifest.json'),'clips':clips,'model_scale':1.3,'model_yaw_radians':3.14159,'muzzle_anchor':'fire_01','anchors':[],'required_godot_animation_fps':480,'source_initial_visibility':[]}
  return p
 def write_profiles(self,profiles): (self.source/'export-profiles.json').write_text(json.dumps({'profiles':profiles}))
 def run_cli(self,*extra):return subprocess.run([sys.executable,str(SCRIPT),'--root',str(self.root),*extra],capture_output=True,text=True)
 def test_additions_merge_without_changing_any_old_profile(self):
  self.write_profiles([self.profile()]);r=self.run_cli('--source',str(self.source));self.assertEqual(r.returncode,0,r.stderr)
  result=json.loads(self.presentation.read_text());self.assertEqual({k:result[k] for k in self.old},self.old);self.assertEqual(set(result)-set(self.old),{'nonomi'});self.assertEqual(result['nonomi']['display_name'],'野宫');self.assertTrue((self.root/'assets/characters/nonomi/nonomi.glb').exists())
 def test_explicit_basic_clip_is_not_overwritten_by_manifest_candidate(self):
  self.write_profiles([self.profile()]);r=self.run_cli('--source',str(self.source));self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(json.loads(self.presentation.read_text())['nonomi']['clips']['basic'],'nonomi_ExplicitBasic')
 def test_validate_entire_input_before_copying_first_profile(self):
  a=self.profile();b=self.profile('iori');(self.source/'iori/color.png').unlink();self.write_profiles([a,b]);r=self.run_cli('--source',str(self.source));self.assertNotEqual(r.returncode,0);self.assertIn('color.png',r.stderr);self.assertEqual(self.presentation.read_bytes(),self.before);self.assertFalse((self.root/'assets/characters/nonomi').exists())
 def test_configure_only_preserves_assets_profiles_and_unrelated_import_options(self):
  profile=self.profile();self.write_profiles([profile]);r=self.run_cli('--source',str(self.source));self.assertEqual(r.returncode,0,r.stderr);raw=self.presentation.read_bytes();dest=self.root/'assets/characters/nonomi';model=(dest/'nonomi.glb').read_bytes()
  config=dest/'nonomi.glb.import';config.write_text('[remap]\nuid="uid://keep"\n[params]\nanimation/fps=30\n_subresources={\n"nodes": {\n"PATH:Other": {"keep": 99},\n"PATH:AnimationPlayer": {"optimizer/enabled": true, "compression/enabled": false}\n},\n"meshes": {"foo": {"save": true}}\n}\ngltf/naming_version=2\n')
  old_dir=self.root/'assets/characters/shiroko';old_dir.mkdir(parents=True);old_config=old_dir/'shiroko.glb.import';old_config.write_text('animation/fps=17\n_subresources={}\n');old_bytes=old_config.read_bytes()
  r=self.run_cli('--source',str(self.source),'--configure-only');self.assertEqual(r.returncode,0,r.stderr);text=config.read_text();self.assertIn('animation/fps=480',text);self.assertIn('"optimizer/enabled": false',text);self.assertIn('"PATH:Other": {"keep": 99}',text);self.assertIn('"meshes": {"foo": {"save": true}}',text);self.assertIn('uid="uid://keep"',text);self.assertEqual(old_config.read_bytes(),old_bytes);self.assertEqual(self.presentation.read_bytes(),raw);self.assertEqual((dest/'nonomi.glb').read_bytes(),model)
 def test_explicit_null_basic_remains_empty(self):
  profile=self.profile();profile['clips']['basic']=None;self.write_profiles([profile]);r=self.run_cli('--source',str(self.source));self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(json.loads(self.presentation.read_text())['nonomi']['clips']['basic'],'')
 def test_unsafe_character_id_is_rejected_before_writes(self):
  profile=self.profile();profile['id']='../escape';self.write_profiles([profile]);r=self.run_cli('--source',str(self.source));self.assertNotEqual(r.returncode,0);self.assertIn('Unsafe character id',r.stderr);self.assertEqual(self.presentation.read_bytes(),self.before);self.assertFalse((self.root/'assets').exists())
 def test_single_windows_separator_traversal_is_rejected(self):
  profile=self.profile();texture_manifest=self.source/'nonomi/textures.json';data=json.loads(texture_manifest.read_text());data['textures'][0]['filename']='..'+chr(92)+'escape.png';texture_manifest.write_text(json.dumps(data));self.write_profiles([profile]);r=self.run_cli('--source',str(self.source));self.assertNotEqual(r.returncode,0);self.assertIn('Unsafe texture filename',r.stderr);self.assertEqual(self.presentation.read_bytes(),self.before);self.assertFalse((self.root/'assets').exists())
 def test_fallback_basic_used_only_when_explicit_key_absent(self):
  self.write_profiles([self.profile(explicit_basic=False)]);r=self.run_cli('--source',str(self.source));self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(json.loads(self.presentation.read_text())['nonomi']['clips']['basic'],'Nonomi_Original_Public01')
class DataMapImportTests(unittest.TestCase):
 setUp = SnapshotImporterTests.setUp
 write_profiles = SnapshotImporterTests.write_profiles
 run_cli = SnapshotImporterTests.run_cli
 DATA_FILES = {'_HairSpecTex': 'packed-a.png', '_MaskTex': 'packed-b.png', '_SourceTex': 'packed-c.png'}
 TEXTURE_IMPORT = ('[remap]\nimporter="texture"\nuid="uid://preserve"\n'
                   '[deps]\nsource_file="res://fixture.png"\n'
                   '[params]\ncompress/mode=0\nprocess/fix_alpha_border=true\n'
                   'process/premult_alpha=false\nmipmaps/generate=false\n')
 MODEL_IMPORT = '[params]\nanimation/fps=30\n_subresources={}\n'

 def profile(self, name='nonomi', explicit_basic=True):
  profile = SnapshotImporterTests.profile(self, name, explicit_basic)
  directory = self.source / name
  manifest_path = directory / 'textures.json'
  manifest = json.loads(manifest_path.read_text())
  material_path = directory / 'materials/body.json'
  material = json.loads(material_path.read_text())
  bindings = material['m_SavedProperties']['m_TexEnvs']
  for index, (slot, filename) in enumerate(self.DATA_FILES.items(), 20):
   (directory / filename).write_bytes(b'PNG data fixture ' + bytes([index]))
   manifest['textures'].append({'path_id': str(index), 'filename': filename})
   bindings.append([slot, {'m_Texture': {'m_PathID': index}, 'm_Scale': {'x': 1, 'y': 1}, 'm_Offset': {'x': 0, 'y': 0}}])
  manifest_path.write_text(json.dumps(manifest))
  material_path.write_text(json.dumps(material))
  return profile

 def imported_fixture(self, names=('nonomi',)):
  profiles = [self.profile(name) for name in names]
  self.write_profiles(profiles)
  result = self.run_cli('--source', str(self.source))
  self.assertEqual(result.returncode, 0, result.stderr)
  for profile in profiles:
   directory = self.root / 'assets/characters' / profile['id']
   (directory / (profile['id'] + '.glb.import')).write_text(self.MODEL_IMPORT)
   for filename in [*self.DATA_FILES.values(), 'color.png', 'unbound_HairSpecTex_Mask.png']:
    (directory / (filename + '.import')).write_text(self.TEXTURE_IMPORT)
  return profiles

 def config_bytes(self):
  return {path: path.read_bytes() for path in self.root.rglob('*.import')}

 def configure(self):
  return self.run_cli('--source', str(self.source), '--configure-only')

 def test_only_selected_bound_data_maps_change_and_assets_metadata_survive(self):
  profiles = self.imported_fixture(('nonomi', 'iori'))
  self.write_profiles(profiles[:1])
  # The selected presentation is authoritative even if the export's old materials differ.
  document = json.loads(self.presentation.read_text())
  document['iori']['materials'] = 'Unselected malformed bindings must be ignored'
  self.presentation.write_text(json.dumps(document))
  (self.source / 'nonomi/materials/body.json').write_text('{}')
  configs = self.config_bytes()
  assets = [self.presentation, *self.root.rglob('*.png'), *self.root.rglob('*.glb'), *self.source.rglob('*')]
  assets = [path for path in assets if path.is_file()]
  snapshots = {path: (path.read_bytes(), path.stat().st_mtime_ns, path.stat().st_mode) for path in assets}
  result = self.configure()
  self.assertEqual(result.returncode, 0, result.stderr)
  selected = self.root / 'assets/characters/nonomi'
  changed = {selected / (name + '.import') for name in self.DATA_FILES.values()}
  changed.add(selected / 'nonomi.glb.import')
  for path, before in configs.items():
   if path in changed and path.suffixes[-2:] == ['.png', '.import']:
    self.assertEqual(path.read_bytes(), before.replace(b'process/fix_alpha_border=true', b'process/fix_alpha_border=false'))
   elif path not in changed:
    self.assertEqual(path.read_bytes(), before, str(path))
  for path, before in snapshots.items():
   self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns, path.stat().st_mode), before, str(path))
  first_pass = self.config_bytes()
  self.assertEqual(self.configure().returncode, 0)
  self.assertEqual(self.config_bytes(), first_pass)

 def test_missing_data_import_rejects_without_partial_model_or_map_changes(self):
  self.imported_fixture(('nonomi', 'iori'))
  missing = self.root / 'assets/characters/iori/packed-c.png.import'
  missing.unlink()
  before = self.config_bytes()
  result = self.configure()
  self.assertNotEqual(result.returncode, 0)
  self.assertIn('packed-c.png.import', result.stderr)
  self.assertEqual(self.config_bytes(), before)

 def test_initial_import_reports_pending_maps_without_partial_configuration(self):
  self.imported_fixture(('nonomi', 'iori'))
  (self.root / 'assets/characters/iori/packed-b.png.import').unlink()
  before = self.config_bytes()
  result = self.run_cli('--source', str(self.source))
  self.assertEqual(result.returncode, 0, result.stderr)
  self.assertEqual(json.loads(result.stdout)['pending_godot_import_configuration'], ['iori'])
  self.assertEqual(self.config_bytes(), before)

 def test_initial_import_configures_bound_data_maps_when_all_imports_exist(self):
  self.imported_fixture()
  result = self.run_cli('--source', str(self.source))
  self.assertEqual(result.returncode, 0, result.stderr)
  self.assertEqual(json.loads(result.stdout)['pending_godot_import_configuration'], [])
  directory = self.root / 'assets/characters/nonomi'
  for filename in self.DATA_FILES.values():
   self.assertIn('process/fix_alpha_border=false', (directory / (filename + '.import')).read_text())
  self.assertEqual((directory / 'color.png.import').read_text(), self.TEXTURE_IMPORT)

 def test_malformed_selected_bindings_reject_before_configuration_writes(self):
  self.imported_fixture()
  original = json.loads(self.presentation.read_text())
  variants = [None, {}, [None], [{'textures': []}], [{'textures': {'_MaskTex': None}}], [{'textures': {'_MaskTex': ''}}]]
  for materials in variants:
   with self.subTest(materials=materials):
    document = dict(original)
    document['nonomi'] = {**original['nonomi'], 'materials': materials}
    self.presentation.write_text(json.dumps(document))
    before = self.config_bytes()
    result = self.configure()
    self.assertNotEqual(result.returncode, 0)
    self.assertEqual(self.config_bytes(), before)

 def test_unsafe_data_resource_paths_reject_before_configuration_writes(self):
  self.imported_fixture()
  original = json.loads(self.presentation.read_text())
  for resource in ['../outside.png', 'res://../outside.png', 'res:///tmp/outside.png', 'res://assets/../outside.png', 'res://assets\\outside.png', 'user://outside.png']:
   with self.subTest(resource=resource):
    original['nonomi']['materials'][0]['textures']['_MaskTex'] = resource
    self.presentation.write_text(json.dumps(original))
    before = self.config_bytes()
    result = self.configure()
    self.assertNotEqual(result.returncode, 0)
    self.assertEqual(self.config_bytes(), before)

 def test_out_of_project_texture_and_import_symlinks_reject_before_writes(self):
  self.imported_fixture()
  directory = self.root / 'assets/characters/nonomi'
  for filename in ['packed-b.png', 'packed-b.png.import']:
   with self.subTest(filename=filename):
    target = directory / filename
    original = target.read_bytes()
    outside = self.base / filename
    outside.write_bytes(original)
    target.unlink()
    target.symlink_to(outside)
    before = self.config_bytes()
    result = self.configure()
    self.assertNotEqual(result.returncode, 0)
    self.assertEqual(self.config_bytes(), before)
    self.assertEqual(outside.read_bytes(), original)
    target.unlink()
    target.write_bytes(original)

 def test_malformed_data_import_is_validated_before_any_import_or_asset_write(self):
  self.imported_fixture()
  target = self.root / 'assets/characters/nonomi/packed-c.png.import'
  malformed = ['[remap]\nprocess/fix_alpha_border=true\n',
               '[params]\nprocess/fix_alpha_border=not_a_bool\n',
               '[params]\nprocess/fix_alpha_border true\n',
               '[params]\n[broken\nprocess/fix_alpha_border=true\n',
               '[params]\nprocess/fix_alpha_border=true\nprocess/fix_alpha_border=false\n',
               '[params]\n[params]\nprocess/fix_alpha_border=true\n']
  for text in malformed:
   for configure_only in [True, False]:
    with self.subTest(text=text, configure_only=configure_only):
     target.write_text(text)
     before = self.config_bytes()
     metadata = self.presentation.read_bytes()
     source_model = self.source / 'nonomi/model.glb'
     source_model.write_bytes(b'glTF changed fixture')
     copied_model = self.root / 'assets/characters/nonomi/nonomi.glb'
     old_model = copied_model.read_bytes()
     result = self.configure() if configure_only else self.run_cli('--source', str(self.source))
     self.assertNotEqual(result.returncode, 0)
     self.assertEqual(self.config_bytes(), before)
     self.assertEqual(self.presentation.read_bytes(), metadata)
     self.assertEqual(copied_model.read_bytes(), old_model)

 def test_color_and_data_aliases_are_rejected_without_changing_either(self):
  self.imported_fixture()
  document = json.loads(self.presentation.read_text())
  textures = document['nonomi']['materials'][0]['textures']
  textures['_MaskTex'] = textures['_MainTex']
  self.presentation.write_text(json.dumps(document))
  before = self.config_bytes()
  result = self.configure()
  self.assertNotEqual(result.returncode, 0)
  self.assertIn('both a data map and _MainTex', result.stderr)
  self.assertEqual(self.config_bytes(), before)

 def test_initial_import_rejects_escaping_symlinks_before_copying_assets(self):
  self.imported_fixture()
  directory = self.root / 'assets/characters/nonomi'
  for filename in ['packed-b.png', 'packed-b.png.import']:
   with self.subTest(filename=filename):
    path = directory / filename
    original = path.read_bytes()
    outside = self.base / filename
    outside.write_bytes(original)
    path.unlink()
    path.symlink_to(outside)
    before = self.config_bytes()
    presentation = self.presentation.read_bytes()
    model = (directory / 'nonomi.glb').read_bytes()
    (self.source / 'nonomi/model.glb').write_bytes(b'glTF replacement')
    result = self.run_cli('--source', str(self.source))
    self.assertNotEqual(result.returncode, 0)
    self.assertEqual(self.config_bytes(), before)
    self.assertEqual(self.presentation.read_bytes(), presentation)
    self.assertEqual((directory / 'nonomi.glb').read_bytes(), model)
    self.assertEqual(outside.read_bytes(), original)
    path.unlink()
    path.write_bytes(original)

 def test_missing_color_import_does_not_block_data_map_configuration(self):
  self.imported_fixture()
  directory = self.root / 'assets/characters/nonomi'
  (directory / 'color.png.import').unlink()
  result = self.configure()
  self.assertEqual(result.returncode, 0, result.stderr)
  self.assertIn('process/fix_alpha_border=false', (directory / 'packed-a.png.import').read_text())

 def test_missing_alpha_option_is_added_only_to_params_and_preserves_crlf(self):
  self.imported_fixture()
  target = self.root / 'assets/characters/nonomi/packed-a.png.import'
  original = b'[remap]\r\nuid="uid://keep"\r\n[params]\r\ncompress/mode=0\r\n[custom]\r\nkeep=true\r\n'
  target.write_bytes(original)
  result = self.configure()
  self.assertEqual(result.returncode, 0, result.stderr)
  self.assertEqual(target.read_bytes(), original.replace(b'[params]\r\n', b'[params]\r\nprocess/fix_alpha_border=false\r\n'))

class SourceAnchorTests(unittest.TestCase):
 setUp=SnapshotImporterTests.setUp
 profile=SnapshotImporterTests.profile
 write_profiles=SnapshotImporterTests.write_profiles
 run_cli=SnapshotImporterTests.run_cli
 def glb(self, profile, nodes):
  import struct
  data=json.dumps({'asset':{'version':'2.0'},'nodes':nodes,'scenes':[{'nodes':[0]}],'scene':0}).encode()
  data+=b' '*((-len(data))%4)
  pathlib.Path(profile['model']).write_bytes(struct.pack('<4sIIII',b'glTF',2,20+len(data),len(data),0x4e4f534a)+data)
 def test_symbolic_anchors_resolve_exact_glb_local_trs_before_writes(self):
  p=self.profile();p['anchors']=['fire_01'];self.glb(p,[{'name':'Root','children':[1]},{'name':'Bip001_Weapon','children':[2]},{'name':'fire_01','translation':[.1,.2,.3],'rotation':[0,0,0,1],'scale':[1,1,1]}]);self.write_profiles([p]);source=pathlib.Path(p['model']).read_bytes()
  r=self.run_cli('--source',str(self.source));self.assertEqual(r.returncode,0,r.stderr)
  anchor=json.loads(self.presentation.read_text())['nonomi']['anchors'][0]
  self.assertEqual(anchor,{'name':'fire_01','path':'Root/Bip001_Weapon/fire_01','local_translation':[.1,.2,.3],'local_rotation':[0,0,0,1],'local_scale':[1,1,1]})
  self.assertEqual(pathlib.Path(p['model']).read_bytes(),source)
  for key in self.old:self.assertEqual(json.loads(self.presentation.read_text())[key],self.old[key])
 def test_legacy_structured_anchors_remain_exact(self):
  p=self.profile();anchor={'name':'fire_01','path':'Root/Weapon/fire_01','local_translation':[1,2,3],'local_rotation':[0,0,0,1],'local_scale':[1,1,1],'provenance':'retained'};p['anchors']=[anchor];self.write_profiles([p]);r=self.run_cli('--source',str(self.source));self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(json.loads(self.presentation.read_text())['nonomi']['anchors'],[anchor])
 def test_ambiguous_missing_matrix_cycle_and_invalid_trs_fail_without_writes(self):
  cases=[
   [{'name':'Root','children':[1,2]},{'name':'fire_01'},{'name':'fire_01'}],
   [{'name':'Root'}],
   [{'name':'Root','children':[1]},{'name':'fire_01','matrix':[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}],
   [{'name':'Root','children':[1]},{'name':'fire_01','children':[0]}],
   [{'name':'Root','children':[1]},{'name':'fire_01','translation':[True,0,0]}],
   [{'name':'Root','children':[1]},{'name':'fire_01','rotation':[0,0,0,0]}],
   [{'name':'Root','children':[1]},{'name':'fire_01','scale':[2,1,1]}],
  ]
  for i,nodes in enumerate(cases):
   with self.subTest(case=i):
    p=self.profile('case'+str(i));p['anchors']=['fire_01'];self.glb(p,nodes);self.write_profiles([p]);r=self.run_cli('--source',str(self.source));self.assertNotEqual(r.returncode,0);self.assertIn('anchor',r.stderr.lower());self.assertEqual(self.presentation.read_bytes(),self.before);self.assertFalse((self.root/'assets').exists())
 def test_malformed_structured_anchor_rejected_before_copy(self):
  p=self.profile();p['anchors']=[{'name':'fire_01','path':'Root/fire_01','local_translation':[0,0,0],'local_rotation':[0,0,0,0]}];self.write_profiles([p]);r=self.run_cli('--source',str(self.source));self.assertNotEqual(r.returncode,0);self.assertIn('anchor',r.stderr.lower());self.assertEqual(self.presentation.read_bytes(),self.before);self.assertFalse((self.root/'assets').exists())

if __name__=='__main__':unittest.main()
