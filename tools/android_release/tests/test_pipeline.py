"""Contract tests for the private, pinned Android packaging path."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))

def load(name):
    path = HERE / (name + '.py')
    if not path.exists():
        raise AssertionError('Missing implementation: ' + str(path))
    spec = importlib.util.spec_from_file_location('android_' + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class Staging(unittest.TestCase):
    def setUp(self):
        self.p = load('release_pipeline')
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_project_override_preserves_game_settings_and_is_idempotent(self):
        source='config_version=5\n[application]\nconfig/name="Blue-A"\n[display]\nwindow/size/viewport_width=100\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        actual=self.p.android_project(source)
        self.assertIn('config/name="Blue-A"',actual)
        self.assertIn('config/icon="res://assets/ui/android_launcher.svg"',actual)
        for line in ['window/size/viewport_width=1280','window/size/viewport_height=900','window/stretch/mode="canvas_items"','window/stretch/aspect="expand"','window/handheld/orientation=0','pointing/emulate_mouse_from_touch=true','textures/vram_compression/import_etc2_astc=true','textures/vram_compression/import_s3tc_bptc=false']:
            self.assertIn(line,actual)
        self.assertEqual(self.p.android_project(actual),actual)
        self.assertEqual(actual.count('window/size/viewport_width='),1)

    def test_preset_reuses_filters_and_has_only_arm64_and_no_permissions(self):
        preset=self.p.android_preset(self.root)
        self.assertIn('architectures/arm64-v8a=true',preset)
        self.assertIn('architectures/armeabi-v7a=false',preset)
        self.assertIn('architectures/x86_64=false',preset)
        self.assertIn('package/unique_name="com.bluea.prototype"',preset)
        self.assertIn('gradle_build/use_gradle_build=false',preset)
        self.assertIn('permissions/internet=false',preset)
        self.assertIn('user_data_backup/allow=false',preset)
        self.assertNotIn('keystore/release_password',preset)
        original=(HERE.parent/'windows_release/export_presets.cfg.in').read_text()
        for key in ('include_filter','exclude_filter'):
            self.assertEqual(self.p.config_value(preset,'preset.0',key),self.p.config_value(original,'preset.0',key))

    def test_integrity_allows_mobile_import_outputs_but_not_source_or_parameters(self):
        source='[remap]\nimporter="texture"\ntype="CompressedTexture2D"\nuid="uid://abc"\npath.s3tc="res://.godot/imported/a.s3tc.ctex"\nmetadata={"vram_texture": true}\n[deps]\nsource_file="res://assets/a.png"\ndest_files=["res://.godot/imported/a.s3tc.ctex"]\n[params]\ncompress/mode=2\nmipmaps/generate=true\n'
        after=source.replace('s3tc','etc2')
        self.assertTrue(self.p.mobile_import_change_allowed(source,after))
        for bad in [after.replace('compress/mode=2','compress/mode=0'),after.replace('uid://abc','uid://evil'),after.replace('assets/a.png','assets/b.png'),after+'\n[other]\nfoo=1\n']:
            self.assertFalse(self.p.mobile_import_change_allowed(source,bad))

    def test_integrity_rejects_extra_gameplay_code_and_tracks_generated_icon(self):
        (self.root/'core').mkdir(); (self.root/'assets/ui').mkdir(parents=True)
        original=b'extends Node\n'
        (self.root/'core/game.gd').write_bytes(original)
        project=self.p.android_project('config_version=5\n')
        (self.root/'project.godot').write_text(project)
        (self.root/'assets/ui/android_launcher.svg').write_bytes((HERE/'launcher_icon.svg').read_bytes())
        (self.root/'export_presets.cfg').write_text('fixture')
        info={'git_object_format':'sha1','files':[{'path':'core/game.gd','git_blob':hashlib.sha1(b'blob '+str(len(original)).encode()+b'\0'+original).hexdigest()}]}
        good=self.p.staging_integrity(self.root,info,{},project,[],'fixture')
        self.assertTrue(good['passed'],good)
        (self.root/'export_presets.cfg').write_text('tampered')
        self.assertFalse(self.p.staging_integrity(self.root,info,{},project,[],'fixture')['passed'])
        (self.root/'export_presets.cfg').write_text('fixture')
        (self.root/'core/injected.gd').write_text('extends Node\n')
        bad=self.p.staging_integrity(self.root,info,{},project,[],'fixture')
        self.assertFalse(bad['passed']);self.assertIn('core/injected.gd',bad['unexpected_extra_files'])

    def test_output_must_be_fresh_and_outside_all_inputs(self):
        repo=self.root/'repo';repo.mkdir()
        with self.assertRaises(ValueError):self.p.validate_output(repo/'output',[repo])
        target=self.root/'dangling';target.symlink_to(self.root/'absent')
        with self.assertRaises(FileExistsError):self.p.validate_output(target,[repo])
        self.assertEqual(self.p.validate_output(self.root/'out',[repo]),self.root/'out')
        self.assertFalse((self.root/'out').exists())

    def test_key_parent_permissions_are_not_changed_when_directory_exists(self):
        parent=self.root/'shared';parent.mkdir(mode=0o755)
        before=parent.stat().st_mode & 0o777
        self.p.prepare_private_key_parent(parent)
        self.assertEqual(parent.stat().st_mode & 0o777,before)
        private=self.root/'new-private';self.p.prepare_private_key_parent(private)
        self.assertEqual(private.stat().st_mode & 0o777,0o700)

    def test_isolated_environment_removes_inherited_signing_and_uses_sdk_preferences(self):
        import os
        old=os.environ.get('GODOT_ANDROID_KEYSTORE_RELEASE_PATH')
        os.environ['GODOT_ANDROID_KEYSTORE_RELEASE_PATH']='/must/not/use'
        try:env=self.p.android_environment(self.root/'scratch',self.root/'sdk',self.root/'java',self.root/'debug.keystore')
        finally:
            if old is None:os.environ.pop('GODOT_ANDROID_KEYSTORE_RELEASE_PATH',None)
            else:os.environ['GODOT_ANDROID_KEYSTORE_RELEASE_PATH']=old
        self.assertEqual(env['GODOT_ANDROID_KEYSTORE_RELEASE_PATH'],str(self.root/'debug.keystore'))
        settings=(Path(env['XDG_CONFIG_HOME'])/'godot/editor_settings-4.6.tres').read_text()
        self.assertIn('export/android/android_sdk_path="'+str(self.root/'sdk')+'"',settings)
        self.assertIn('export/android/java_sdk_path="'+str(self.root/'java')+'"',settings)
        self.assertEqual(Path(env['HOME']).stat().st_mode&0o777,0o700)

class ApkResources(unittest.TestCase):
    def setUp(self):
        self.v=load('verify_apk')
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)

    def fixture(self,extra=None,raw=b'{}'):
        entries={'AndroidManifest.xml':b'manifest','classes.dex':b'dex','lib/arm64-v8a/libgodot_android.so':b'ELF',
            'assets/project.binary':b'project','assets/game.tscn.remap':b'[remap]\npath="res://.godot/exported/scene.scn"\n',
            'assets/.godot/exported/scene.scn':b'scene','assets/data/test.json':raw,
            'assets/assets/a.wav.import':b'[remap]\nimporter="wav"\npath="res://.godot/imported/a.sample"\n',
            'assets/.godot/imported/a.sample':b'PCM'}
        entries.update(extra or {})
        apk=self.root/'fixture.apk'
        with zipfile.ZipFile(apk,'w') as z:
            for k,v in entries.items():z.writestr(k,v)
        manifest={'files':[{'category':'runtime_json','path':'data/test.json','sha256':hashlib.sha256(b'{}').hexdigest()}, {'category':'ordinary_audio_streams','path':'assets/a.wav','sha256':'unused'}], 'excluded_effect_source_json':[]}
        return apk,manifest

    def test_raw_hash_and_import_target_presence_are_required(self):
        apk,m=self.fixture();r=self.v.verify_resources(apk,m)
        self.assertTrue(r['passed'],r)
        apk,m=self.fixture(raw=b'bad');self.assertFalse(self.v.verify_resources(apk,m)['passed'])
        apk,m=self.fixture({'assets/assets/a.wav.import':b'[remap]\npath="res://.godot/imported/missing.sample"\n'})
        r=self.v.verify_resources(apk,m);self.assertFalse(r['passed']);self.assertTrue(r['missing_import_targets'])

    def test_source_import_identity_rejects_swapped_valid_payloads(self):
        first=b'[remap]\npath="res://.godot/imported/a.sample"\n'
        second=b'[remap]\npath="res://.godot/imported/b.sample"\n'
        stage=self.root/'stage'
        for name,data in {'assets/a.wav.import':first,'assets/b.wav.import':second,
                          '.godot/imported/a.sample':b'PCM','.godot/imported/b.sample':b'OTHER'}.items():
            target=stage/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
        extras={'assets/assets/b.wav.import':second,'assets/.godot/imported/b.sample':b'OTHER'}
        apk,m=self.fixture(extras)
        self.assertTrue(self.v.verify_resources(apk,m,stage)['passed'])
        apk,m=self.fixture(dict(extras,**{'assets/assets/a.wav.import':second,'assets/assets/b.wav.import':first}))
        report=self.v.verify_resources(apk,m,stage)
        self.assertFalse(report['passed'],'Valid payloads must still map to their original source resources')
        self.assertEqual(report['source_import_remap_mismatched'],['assets/a.wav.import','assets/b.wav.import'])

    def test_forbidden_and_non_arm64_entries_rejected(self):
        for path in ['assets/tests/test.gd','assets/assets/a/source_objects/raw.obj','assets/evidence/a.png','assets/private.keystore','lib/x86/libgodot_android.so','assets/.godot/imported/desktop.s3tc.ctex','assets/.godot/imported/desktop.bptc.ctex']:
            apk,m=self.fixture({path:b'bad'});self.assertFalse(self.v.verify_resources(apk,m)['passed'],path)

    def test_duplicate_and_unsafe_zip_members_are_rejected(self):
        apk,m=self.fixture({'assets/../escape':b'bad'})
        with self.assertRaises(ValueError):self.v.verify_resources(apk,m)
        apk,m=self.fixture()
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            with zipfile.ZipFile(apk,'a') as z:z.writestr('assets/project.binary',b'bad')
        with self.assertRaises(ValueError):self.v.verify_resources(apk,m)

    def test_launcher_alias_is_accepted_when_aapt_badging_omits_it(self):
        badging="package: name='com.bluea.prototype'\nsdkVersion:'24'\ntargetSdkVersion:'36'\nnative-code: 'arm64-v8a'\n"
        xml='A: android:screenOrientation(0x0101001e)=(type 0x10)0x0\nA: android:allowBackup(0x01010280)=(type 0x12)0x0\n'
        alias='      E: activity-alias (line=47)\n        A: android:name(0x01010003)="com.godot.game.GodotAppLauncher"\n        A: android:exported(0x01010010)=(type 0x12)0xffffffff\n        A: android:targetActivity(0x01010202)="com.godot.game.GodotApp"\n        E: intent-filter (line=51)\n          E: action (line=52)\n            A: android:name(0x01010003)="android.intent.action.MAIN"\n          E: category (line=55)\n            A: android:name(0x01010003)="android.intent.category.LAUNCHER"\n      E: service (line=60)\n'
        self.assertTrue(self.v.verify_metadata(badging,'',xml+alias)['passed'])
        self.assertFalse(self.v.verify_metadata(badging,'',xml+alias.replace('0xffffffff','0x0'))['passed'])
        self.assertFalse(self.v.verify_metadata(badging,'',xml+alias.replace('category.LAUNCHER','category.DEFAULT'))['passed'])

    def test_audio_verification_pack_contains_only_actual_apk_audio_dependencies(self):
        apk,manifest=self.fixture()
        target=self.root/'audio.zip'
        count=self.v.make_audio_verification_pack(apk,manifest,target)
        self.assertEqual(count,2)
        with zipfile.ZipFile(target) as z:
            self.assertEqual(set(z.namelist()),{'assets/a.wav.import','.godot/imported/a.sample'})
            self.assertEqual(z.read('.godot/imported/a.sample'),b'PCM')
        with self.assertRaises(FileExistsError):self.v.make_audio_verification_pack(apk,manifest,target)

    def test_permission_package_and_manifest_contract(self):
        badging="package: name='com.bluea.prototype' versionCode='1' versionName='0.1.0-private'\nsdkVersion:'24'\ntargetSdkVersion:'36'\nlaunchable-activity: name='com.godot.game.GodotApp'\nnative-code: 'arm64-v8a'\n"
        xml='A: android:screenOrientation(0x0101001e)=(type 0x10)0x0\nA: android:allowBackup(0x01010280)=(type 0x12)0x0\n'
        self.assertTrue(self.v.verify_metadata(badging,'package: com.bluea.prototype\n',xml)['passed'])
        for bad in [badging.replace('com.bluea.prototype','com.example.app'),badging+"uses-permission: name='android.permission.INTERNET'\n",badging+"application-debuggable\n"]:
            self.assertFalse(self.v.verify_metadata(bad,'',xml)['passed'])
        self.assertFalse(self.v.verify_metadata(badging,'',xml.replace('screenOrientation(0x0101001e)=(type 0x10)0x0','screenOrientation(0x0101001e)=(type 0x10)0x1'))['passed'])

class CLI(unittest.TestCase):
    def test_dry_run_is_read_only_and_requires_full_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);repo=root/'repo';repo.mkdir()
            def git(*args):return subprocess.check_output(['git','-C',str(repo),*args],text=True,stderr=subprocess.DEVNULL).strip()
            git('init');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid')
            for path in ('project.godot','game.tscn','core/a.gd','scripts/a.gd','shaders/a.gdshader','assets/a.txt','data/a.json','vfx/a.gd'):
                file=repo/path;file.parent.mkdir(parents=True,exist_ok=True);file.write_text('fixture')
            git('add','.');git('commit','-m','fixture');commit=git('rev-parse','HEAD')
            argv=[sys.executable,str(HERE/'release_pipeline.py'),'--repo',str(repo),'--commit',commit,'--output-root',str(root/'output'),'--keystore',str(root/'signing/debug.keystore'),'--dry-run']
            result=subprocess.run(argv,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            report=json.loads(result.stdout);self.assertEqual(report['source_commit'],commit)
            self.assertFalse(report['godot_executed']);self.assertFalse((root/'output').exists());self.assertFalse((root/'signing').exists())
            for bad in ('HEAD',commit[:12]):
                invalid=argv.copy();invalid[invalid.index(commit)]=bad
                self.assertNotEqual(subprocess.run(invalid,capture_output=True).returncode,0)

if __name__=='__main__':unittest.main()
