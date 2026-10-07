import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parents[1]

def load_module(name):
    path = HERE / (name + '.py')
    if not path.exists():
        raise AssertionError(f'Missing implementation: {path.name}')
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class Helpers(unittest.TestCase):
    def setUp(self):
        self.p = load_module('release_pipeline')
        self.tmp = tempfile.TemporaryDirectory(dir=HERE)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_paths_reject_escape_and_symlinks(self):
        for value in ['../secret', '/tmp/secret', 'assets/../../secret', 'assets\\secret', 'res://../secret']:
            with self.assertRaises(ValueError, msg=value):
                self.p.safe_relative(value)
        self.assertEqual(self.p.safe_relative('res://assets/a.png'), 'assets/a.png')
        (self.root/'link').symlink_to('/tmp')
        with self.assertRaises(ValueError):
            self.p.assert_plain_tree(self.root)

    def test_archive_rejects_link_and_outside_root(self):
        for name, kind in [('project.godot', tarfile.SYMTYPE), ('../escape', tarfile.REGTYPE), ('tests/test.gd', tarfile.REGTYPE)]:
            b = io.BytesIO()
            with tarfile.open(fileobj=b, mode='w') as archive:
                item=tarfile.TarInfo(name);item.type=kind;item.linkname='/tmp'
                archive.addfile(item, io.BytesIO(b''))
            b.seek(0)
            with tarfile.open(fileobj=b) as archive:
                with self.assertRaises(ValueError):
                    self.p.extract_archive(archive,self.root/'staging')

    def test_diagnostics_preserve_known_issue_and_detect_any_change(self):
        base={'skill_icons':37,'passed':True,'failures':[],'failure_count':0, 'raw_meshes':171,'vfx_pixels':279,'texture_metadata':279,'models':14,'vfx_timelines_spawned':28,
              'audio_bus_layouts':1,'audio_peak_limiters':1,'audio_streams':43,'ordinary_audio_streams':96,'ordinary_audio_bindings':28,'ordinary_audio_scheduled':28,'ordinary_audio_issues':[],
              'dependency_diagnostics':[{'code':'missing_material','context':'FX_Nonomi_Original_Ex01_Motion_Fire_01/smoke'}], 'vfx_issues':[], 'vfx_native_issues':[{'code':'unsupported_shape','context':'one'}]}
        result=self.p.compare_runtime_reports(base,base,True)
        self.assertTrue(result['passed']);self.assertEqual(len(result['known_source_diagnostics']),1)
        changed=json.loads(json.dumps(base));changed['vfx_native_issues'].append({'code':'unsupported_shape','context':'two'})
        self.assertFalse(self.p.compare_runtime_reports(base,changed,True)['passed'])
        self.assertFalse(self.p.compare_runtime_reports(base,base,False)['passed'])
        changed=json.loads(json.dumps(base));changed['dependency_diagnostics']=[{'code':'missing_textures','context':'oops'}]
        self.assertFalse(self.p.compare_runtime_reports(changed,changed,True)['passed'])
        changed=json.loads(json.dumps(base));changed['skill_icons']=36
        self.assertFalse(self.p.compare_runtime_reports(base,changed,True)['passed'])
        changed=json.loads(json.dumps(base));changed['raw_meshes']=170
        self.assertFalse(self.p.compare_runtime_reports(changed,changed,True)['passed'])

    def test_zip_allowlist_and_deterministic_bytes(self):
        folder=self.root/'Blue-A-Windows-x86_64';folder.mkdir()
        (folder/'Blue-A.exe').write_bytes(b'not-executed')
        (folder/'evidence.log').write_text('must not ship')
        with self.assertRaises(ValueError):self.p.make_zip(folder,self.root/'bad.zip',1700000000)
        (folder/'evidence.log').unlink()
        self.p.make_zip(folder,self.root/'one.zip',1700000000)
        self.p.make_zip(folder,self.root/'two.zip',1700000000)
        self.assertEqual((self.root/'one.zip').read_bytes(),(self.root/'two.zip').read_bytes())
        with self.assertRaises(FileExistsError):self.p.make_zip(folder,self.root/'one.zip',1700000000)
        with zipfile.ZipFile(self.root/'one.zip') as z:self.assertEqual(z.namelist(),['Blue-A-Windows-x86_64/Blue-A.exe'])

    def test_existing_output_is_never_reused(self):
        with self.assertRaises(FileExistsError):self.p.require_fresh_output(self.root)

    def test_template_pe_validation_and_hash(self):
        data=bytearray(512);data[:2]=b'MZ';struct.pack_into('<I',data,0x3c,128);data[128:132]=b'PE\0\0';struct.pack_into('<H',data,132,0x8664)
        path=self.root/'test.exe';path.write_bytes(data)
        self.assertEqual(self.p.pe_machine(path),0x8664)
        data[128]=0;path.write_bytes(data)
        with self.assertRaises(ValueError):self.p.pe_machine(path)

class Manifest(unittest.TestCase):
    def test_manifest_discovers_referenced_data_and_extraction_exclusions(self):
        m=load_module('dependency_manifest')
        with tempfile.TemporaryDirectory(dir=HERE) as directory:
            root=Path(directory)
            def put(name, content):
                p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(content) if not isinstance(content,str) else content)
            put('data/character-presentations.json',{'unit':{'model_path':'res://assets/characters/unit/unit.glb','materials':[{'textures':{'main':'res://assets/characters/unit/body.png'}}], 'clips':{'attack_fire':'fire','reload':'reload'}}})
            put('data/effects/battle-events-compact.json',{'activeRoster':['unit']})
            put('data/skill-icons.json',{'assets':{'skill/test':{'path':'res://assets/ui/skill_icons/test.webp','sha256':hashlib.sha256(b'contents').hexdigest()}},'characters':{'unit':dict.fromkeys(['ex','basic','sub'],'skill/test')}})
            put('assets/ui/skill_icons/test.webp','contents')
            put('data/audio/native-skill-sfx.json',{'records':[{'resourcePath':'res://assets/audio/x.wav'}]})
            from test_ordinary_audio import ordinary_fixture
            ordinary_fixture(root)
            for p in ['assets/characters/unit/unit.glb','assets/characters/unit/body.png','assets/ui/portraits/unit.png','assets/audio/x.wav','data/effects/resources/CAB-x/Mesh-1.obj','data/effects/resources/CAB-x/Texture2D-1.png']:put(p,'contents')
            put('data/effects/resources/CAB-x/Texture2D-1.json',{'name':'texture'})
            put('data/effects/resources/CAB-x/Material-1.json',{'name':'embedded'})
            result=m.build_manifest(root)
            counts=result['summary']['counts']
            self.assertEqual(counts['mesh_raw'],1);self.assertEqual(counts['character_models'],1)
            self.assertEqual(counts['vfx_texture_json'],1);self.assertEqual(counts['audio_streams'],1)
            self.assertEqual(counts['ordinary_audio_streams'],1);self.assertEqual(counts['audio_runtime_scripts'],2)
            self.assertEqual(counts.get('audio_bus_layout'),1)
            self.assertEqual(result['excluded_effect_source_json'],['data/effects/resources/CAB-x/Material-1.json'])
            raw=[x for x in result['files'] if x['category']=='mesh_raw'][0]
            self.assertEqual(raw['sha256'],hashlib.sha256(b'contents').hexdigest())
            (root/'assets/ui/skill_icons/test.webp').unlink()
            with self.assertRaises(ValueError):m.build_manifest(root)
            put('assets/ui/skill_icons/test.webp','wrong pixels')
            with self.assertRaises(ValueError):m.build_manifest(root)
            put('assets/ui/skill_icons/test.webp','contents')
            (root/'assets/characters/unit/body.png').unlink()
            with self.assertRaises(ValueError):m.build_manifest(root)

    def test_keep_overrides_only_raw_obj_and_vfx_png(self):
        p=load_module('release_pipeline')
        with tempfile.TemporaryDirectory(dir=HERE) as directory:
            root=Path(directory)
            paths=['data/effects/m.obj','data/effects/m.obj.nativeobj','data/effects/t.png','assets/characters/u.png']
            rows=[]
            for i,name in enumerate(paths):
                file=root/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(b'original')
                rows.append({'path':name,'category':['mesh_raw','mesh_raw','vfx_texture_png','character_textures'][i]})
            changed=p.keep_raw_imports(root,{'files':rows})
            self.assertEqual(changed,['data/effects/m.obj.import','data/effects/t.png.import'])
            self.assertIn('importer="keep"',(root/(paths[0]+'.import')).read_text())
            for path in paths:self.assertEqual((root/path).read_bytes(),b'original')
            self.assertFalse((root/(paths[3]+'.import')).exists())

class CLI(unittest.TestCase):
    def test_no_execute_is_read_only_plan_and_rejects_symbolic_commit(self):
        with tempfile.TemporaryDirectory(dir=HERE) as directory:
            root=Path(directory);repo=root/'repo';repo.mkdir()
            def git(*args):return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.DEVNULL,text=True).strip()
            git('init');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid')
            for name in ['project.godot','game.tscn']:(repo/name).write_text('fixture')
            for name in ['core','scripts','shaders','assets','data','vfx']:
                (repo/name).mkdir();(repo/name/'file.txt').write_text('fixture')
            git('add','.');git('commit','-m','fixture');commit=git('rev-parse','HEAD')
            command=[sys.executable,str(HERE/'release_pipeline.py'),'--repo',str(repo),'--commit',commit,'--output-root',str(root/'out'),'--templates',str(root/'templates'),'--dry-run']
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            plan=json.loads(result.stdout);self.assertEqual(plan['source_commit'],commit)
            self.assertFalse((root/'out').exists());self.assertFalse(plan['godot_executed'])
            command[command.index(commit)]='HEAD'
            self.assertNotEqual(subprocess.run(command,capture_output=True).returncode,0)

if __name__=='__main__':unittest.main()

class PackReader(unittest.TestCase):
    def test_reader_checks_hashes_and_dynamic_extraction_list(self):
        p=load_module('verify_pck')
        with tempfile.TemporaryDirectory(dir=HERE) as directory:
            root=Path(directory);pack=root/'fixture.pck';out=root/'report.json'
            names={'project.binary':b'project','game.tscn':b'scene','data/effects/x/Material-1.json':b'{}'}
            header=struct.pack('<4s5IQ',b'GDPC',2,4,6,3,0,0)+b'\0'*64+struct.pack('<I',len(names))
            offset=len(header)+sum(4+len(k.encode())+8+8+16+4 for k in names)
            directory_bytes=b'';data=b''
            for name,content in names.items():
                encoded=name.encode();directory_bytes+=struct.pack('<I',len(encoded))+encoded+struct.pack('<QQ',offset,len(content))+hashlib.md5(content).digest()+struct.pack('<I',0)
                data+=content;offset+=len(content)
            pack.write_bytes(header+directory_bytes+data)
            manifest={'files':[],'excluded_effect_source_json':['data/effects/x/Material-1.json']}
            with contextlib.redirect_stdout(io.StringIO()):result=p.verify(pack,manifest,out)
            self.assertFalse(result);self.assertEqual(json.loads(out.read_text())['leaked_extraction_json'],['data/effects/x/Material-1.json'])
            bad=bytearray(pack.read_bytes());bad[-1]^=1;pack.write_bytes(bad)
            with self.assertRaises((AssertionError,ValueError)):p.inspect_pack(pack)

class StrictGates(unittest.TestCase):
    def test_stage_integrity_allows_only_exact_keep_sidecars(self):
        p=load_module('release_pipeline')
        with tempfile.TemporaryDirectory(dir=HERE) as directory:
            root=Path(directory);(root/'source.gd').write_bytes(b'hello')
            oid=hashlib.sha1(b'blob 5\0hello').hexdigest()
            info={'git_object_format':'sha1','files':[{'path':'source.gd','git_blob':oid}]}
            self.assertTrue(p.stage_integrity(root,info)['passed'])
            (root/'source.gd').write_bytes(b'HELLO')
            self.assertFalse(p.stage_integrity(root,info)['passed'])

    def test_cli_rejects_dangling_output_symlink_before_resolving(self):
        with tempfile.TemporaryDirectory(dir=HERE) as directory:
            root=Path(directory);link=root/'output';link.symlink_to(root/'does-not-exist')
            cmd=[sys.executable,str(HERE/'release_pipeline.py'),'--repo',str(root),'--commit','0'*40,'--output-root',str(link),'--templates',str(root),'--dry-run']
            result=subprocess.run(cmd,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('Output root already exists',result.stderr)
