#!/usr/bin/env python3
"""Pinned, isolated Blue-A Windows candidate builder. Dry-run unless --execute."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import time
import zipfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from dependency_manifest import build_manifest, nonomi_null_material, safe_relative, sha256, RAW_CATEGORIES
from verify_pck import verify

ROOTS = ('project.godot', 'game.tscn', 'core', 'scripts', 'shaders', 'assets', 'data', 'vfx')
GODOT = '/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64'
ENGINE_SHA256 = 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
TEMPLATES = {
 'windows_release_x86_64.exe': (104659456, '91724f15024a3a545e28ccd83134403d31ce2323a38e51c95e4dfa282f732ab6'),
 'windows_release_x86_64_console.exe': (188928, '8c0d228f34db4d6a191b9a2247ec8cb595ac33357ac20c985484f21dc845f69c'),
 'version.txt': (13, '4855bd38072b77c73c45739cf6a6787d7df790a368b0a437102f352650e6186b')}
EXPECTED = {'mesh_raw':171, 'vfx_texture_png':279, 'vfx_texture_json':279, 'character_models':14,
            'audio_streams':43, 'ordinary_audio_streams':96, 'audio_runtime_scripts':2, 'audio_bus_layout':1}
COUNTERS = {'skill_icons':37, 'raw_meshes':171, 'vfx_pixels':279, 'texture_metadata':279, 'models':14, 'vfx_timelines_spawned':28,
            'audio_streams':43, 'ordinary_audio_streams':96, 'ordinary_audio_bindings':28, 'ordinary_audio_scheduled':28,
            'audio_bus_layouts':1, 'audio_peak_limiters':1}
KNOWN_DIAGNOSTIC = {'code':'missing_material','context':'FX_Nonomi_Original_Ex01_Motion_Fire_01/smoke'}
PACKAGE_FILES = {'Blue-A.exe','Blue-A.console.exe','Blue-A.pck','README.zh-CN.txt','ASSET-NOTICE.zh-CN.txt',
 'GODOT-LICENSE.txt','GODOT-THIRD-PARTY-NOTICES.txt','BUILD-MANIFEST.json','SHA256SUMS.txt'}

def write_json(path, data):
    Path(path).write_text(json.dumps(data,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')

def require_fresh_output(path):
    if Path(path).exists() or Path(path).is_symlink():
        raise FileExistsError('Output root already exists; choose a new root: '+str(path))

def assert_plain_tree(root):
    for path in Path(root).rglob('*'):
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise ValueError('Symlink/special file in staging: '+str(path))

def extract_archive(archive, destination):
    destination=Path(destination)
    for member in archive:
        path=safe_relative(member.name.rstrip('/'))
        if path.split('/')[0] not in ROOTS or not (member.isfile() or member.isdir()):
            raise ValueError('Unexpected archive member: '+member.name)
        target=destination/path
        if member.isdir():target.mkdir(parents=True,exist_ok=True);continue
        target.parent.mkdir(parents=True,exist_ok=True)
        with archive.extractfile(member) as source, target.open('xb') as output:
            shutil.copyfileobj(source,output)
        target.chmod(0o755 if member.mode & 0o111 else 0o644)

def git(repo,*args):
    env=dict(os.environ,GIT_OPTIONAL_LOCKS='0',GIT_TERMINAL_PROMPT='0')
    return subprocess.check_output(['git','-C',str(repo),*args],env=env).decode().strip()

def source_info(repo, commit):
    if not re.fullmatch(r'[0-9a-fA-F]{40}|[0-9a-fA-F]{64}',commit):
        raise ValueError('--commit must be a full immutable commit hash, not a branch/tag/HEAD')
    resolved=git(repo,'rev-parse','--verify',commit+'^{commit}')
    if resolved.lower()!=commit.lower():raise ValueError('Commit does not resolve exactly')
    listing=git(repo,'ls-tree','-r',commit,'--',*ROOTS)
    rows=[]
    for line in listing.splitlines():
        metadata,path=line.split('\t',1);mode,kind,oid=metadata.split()
        if mode not in ('100644','100755') or kind!='blob':raise ValueError('Unsupported git entry: '+line)
        rows.append({'path':safe_relative(path),'mode':mode,'git_blob':oid})
    if not set(ROOTS).issubset({r['path'].split('/')[0] for r in rows}):raise ValueError('Commit lacks required runtime roots')
    return {'source_commit':resolved,'source_tree':git(repo,'rev-parse',commit+'^{tree}'),
            'source_commit_epoch':int(git(repo,'show','-s','--format=%ct',commit)),
            'git_object_format':git(repo,'rev-parse','--show-object-format'),'files':rows}

def archive_commit(repo, commit, destination):
    process=subprocess.Popen(['git','-C',str(repo),'archive','--format=tar',commit,'--',*ROOTS],stdout=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=process.stdout,mode='r|') as archive:extract_archive(archive,destination)
        if process.wait()!=0:raise RuntimeError('git archive failed')
    finally:
        if process.poll() is None:process.kill();process.wait()
        process.stdout.close()
    assert_plain_tree(destination)

def stage_integrity(stage, info, overrides=()):
    overrides=set(overrides);changed=[];checked=0
    for row in info['files']:
        p=Path(stage)/row['path']
        if not p.is_file() or p.is_symlink():changed.append(row['path']);continue
        if row['path'] in overrides:
            expected='[remap]\n\nimporter="keep"\n\n[deps]\n\nsource_file="res://'+row['path'].removesuffix('.import')+'"\n'
            if p.read_text()!=expected:changed.append(row['path'])
            continue
        h=hashlib.new(info['git_object_format']);h.update(('blob '+str(p.stat().st_size)+'\0').encode())
        with p.open('rb') as f:
            for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
        if h.hexdigest()!=row['git_blob']:changed.append(row['path'])
        checked+=1
    return {'passed':not changed,'tracked_files':len(info['files']),'unchanged_git_blobs':checked,
            'allowed_keep_sidecars':sorted(overrides),'unexpected_changed_files':changed}

def keep_raw_imports(stage, manifest):
    paths=sorted({row['path'] for row in manifest['files'] if
        row['category']=='vfx_texture_png' or (row['category']=='mesh_raw' and row['path'].endswith('.obj'))})
    for path in paths:
        (Path(stage)/(path+'.import')).write_text('[remap]\n\nimporter="keep"\n\n[deps]\n\nsource_file="res://'+path+'"\n')
    return [p+'.import' for p in paths]

def pe_machine(path):
    with Path(path).open('rb') as f:
        if f.read(2)!=b'MZ':raise ValueError('Not a PE executable')
        f.seek(0x3c);raw=f.read(4)
        if len(raw)!=4:raise ValueError('Truncated PE header')
        f.seek(struct.unpack('<I',raw)[0])
        if f.read(4)!=b'PE\0\0':raise ValueError('Invalid PE signature')
        raw=f.read(2)
        if len(raw)!=2:raise ValueError('Truncated PE machine')
        return struct.unpack('<H',raw)[0]

def verify_templates(root):
    rows=[]
    for name,(size,digest) in TEMPLATES.items():
        p=Path(root)/name
        if not p.is_file() or p.stat().st_size!=size or sha256(p)!=digest:
            raise ValueError('Template size/hash mismatch: '+str(p))
        row={'file':name,'bytes':size,'sha256':digest}
        if name.endswith('.exe'):
            row['pe_machine']=pe_machine(p)
            if row['pe_machine']!=0x8664:raise ValueError('Template is not x86_64')
        rows.append(row)
    return {'engine_version':'4.6.3.stable','members':rows,
        'official_archive':'https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz',
        'official_archive_published_sha256':'3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8',
        'whole_archive_hash_verified':False,'member_hashes_verified':True,
        'retrieval':'Previously retrieved official HTTPS ZIP byte ranges; no download during this build'}

def canonical_issues(items):
    return sorted(json.dumps(item,ensure_ascii=False,sort_keys=True,separators=(',',':')) for item in items)

def compare_runtime_reports(source, packed, null_material, animation_profiles=()):
    failures=[]
    animation_profiles=sorted(animation_profiles)
    for label,report in [('source',source),('pack',packed)]:
        if report.get('passed') is not True or report.get('failure_count')!=0 or report.get('failures')!=[]:
            failures.append(label+' harness failed')
        for key,value in COUNTERS.items():
            if report.get(key)!=value:failures.append(label+' '+key+' expected '+str(value))
        for issue in report.get('dependency_diagnostics',[]):
            if issue!=KNOWN_DIAGNOSTIC or not null_material:failures.append(label+' unexpected dependency diagnostic '+str(issue))
        if report.get('ordinary_audio_issues') != []:failures.append(label+' ordinary audio diagnostics missing or nonempty')
        if sorted(report.get('animation_override_profiles',[])) != animation_profiles:
            failures.append(label+' animation override profiles differ from declared dependencies')
        for key in ('animation_override_models','animation_override_libraries'):
            value=report.get(key,0)
            if type(value) is not int or value != len(animation_profiles):failures.append(label+' '+key+' expected '+str(len(animation_profiles)))
        for key in ('animation_override_clips','animation_override_keys','animation_override_samples'):
            value=report.get(key,0)
            if type(value) is not int or value < len(animation_profiles):failures.append(label+' missing animation content checks: '+key)
        if report.get('animation_override_issues',None if animation_profiles else []) != []:failures.append(label+' animation override diagnostics missing or nonempty')
        details=report.get('animation_override_details',{})
        if not isinstance(details,dict) or sorted(details) != animation_profiles:
            failures.append(label+' animation override details missing')
    if source.get('animation_override_details',{}) != packed.get('animation_override_details',{}):
        failures.append('animation_override_details source/pack mismatch')
    for key in ('vfx_issues','vfx_native_issues','dependency_diagnostics','ordinary_audio_issues','ordinary_audio_choices','limitations'):
        if canonical_issues(source.get(key,[]))!=canonical_issues(packed.get(key,[])):failures.append(key+' source/pack mismatch')
    for key in ('raw_files','raw_meshes','vfx_pixels','texture_metadata','models','character_textures','portraits','skill_icons','audio_streams','ordinary_audio_streams','ordinary_audio_bindings','ordinary_audio_scheduled','audio_bus_layouts','audio_peak_limiters','shaders','clips','vfx_timelines_spawned','animation_override_models','animation_override_libraries','animation_override_clips','animation_override_keys','animation_override_samples'):
        if source.get(key)!=packed.get(key):failures.append(key+' source/pack mismatch')
    return {'passed':not failures,'failures':failures,'diagnostics_identical':not any('mismatch' in s for s in failures),
        'known_source_diagnostics':source.get('dependency_diagnostics',[]),'nonomi_source_material_null':null_material,
        'source_dependency_diagnostics':source.get('dependency_diagnostics',[]),'pack_dependency_diagnostics':packed.get('dependency_diagnostics',[])}

def make_zip(folder, path, epoch):
    folder=Path(folder);path=Path(path)
    assert_plain_tree(folder)
    members=sorted(folder.iterdir())
    if any(not p.is_file() or p.name not in PACKAGE_FILES for p in members):raise ValueError('Unexpected file in distributable folder')
    date=time.gmtime(max(epoch,315532800))[:6]
    with path.open('xb') as stream, zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for file in members:
            info=zipfile.ZipInfo(folder.name+'/'+file.name,date_time=date);info.compress_type=zipfile.ZIP_DEFLATED
            info.create_system=3;info.external_attr=(0o100644<<16)
            with file.open('rb') as src,z.open(info,'w',force_zip64=True) as dst:shutil.copyfileobj(src,dst)
    with zipfile.ZipFile(path) as z:
        if z.testzip() is not None:raise ValueError('ZIP CRC verification failed')
        for item in z.infolist():
            with z.open(item) as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
            if digest!=sha256(folder/Path(item.filename).name):raise ValueError('ZIP content mismatch')

def environment(root):
    env=os.environ.copy()
    for key,relative in {'HOME':'home','XDG_DATA_HOME':'data','XDG_CONFIG_HOME':'config','XDG_CACHE_HOME':'cache','XDG_STATE_HOME':'state','XDG_RUNTIME_DIR':'runtime','TMPDIR':'tmp'}.items():
        p=Path(root)/relative;p.mkdir(parents=True,exist_ok=True);p.chmod(0o700);env[key]=str(p)
    env['GODOT_SILENCE_ROOT_WARNING']='1'
    return env

def run_godot(command, cwd, env, log, timeout):
    # This is the only Godot-launching function; reachable only behind --execute.
    with Path(log).open('xb') as output:
        result=subprocess.run(command,cwd=cwd,env=env,stdout=output,stderr=subprocess.STDOUT,timeout=timeout)
    if result.returncode:raise RuntimeError('Godot failed ('+str(result.returncode)+'): '+str(log))
    errors=[line for line in Path(log).read_text().splitlines() if re.search(r'(ERROR:|SCRIPT ERROR:|WARNING:)',line)]
    if errors:raise RuntimeError('Godot diagnostics require review: '+str(log)+' '+str(errors[:4]))

def readme(commit, epoch):
    return f'''Blue-A 自走棋 · Windows x86_64 私人候选包
源码检查点：{commit}
源码提交时间（UTC）：{datetime.fromtimestamp(epoch,timezone.utc).isoformat()}
Godot 4.6.3 Standard / Compatibility OpenGL

完整解压后双击 Blue-A.exe；Blue-A.pck 必须放在同一目录。Blue-A.console.exe 为可选诊断启动器。无需安装 Godot。
启动后先进入主菜单，可新游戏、继续游戏、局域网联机、设置或退出。离线单人模式内含七名本地 AI；无需管理员权限、浏览器或服务器。商店招募角色并部署上阵；准备阶段可在己方半场自由拖动布阵，不吸附格子，不能重叠或放进障碍物。点击开始战斗，结算后进入下一回合。六轮积分赛胜2、平1、负0，最后显示排名，可再来一局或返回主菜单。
新局初始上阵上限4人，升级后最多5人；备战席最多9人。三个同名一星角色自动合成二星，只升星一次；二星解锁手动EX。左键选人、右键战术转移，数字键1–5选择EX并按指示瞄准确认；共享能量初始4、上限10，每2秒恢复1，个人EX冷却6秒。
新局60秒进入加时，10秒内逐步减弱治疗及新护盾、提高伤害；90秒按双方剩余总HP决胜，高者胜、相同平局，护盾不计入HP。45–70秒为普通回合调校目标，当前代表性实测尚未完全达到。
游戏菜单可以返回主菜单。战斗中返回会确认，并回到本场开战前准备；保存失败或检查点发生变化时，需要明确确认放弃未保存进度。继续旧存档保留该局旧规则，新游戏才使用当前规则。
招募卡显示同名一星的合成进度；悬停可查看购买后的变化。刷新按钮显示实际费用；选中角色后悬停刷新按钮，可查看当前等级下招募该角色的单格概率提示，概率不保证命中。
Esc或菜单按钮打开菜单/设置，可保存、读取，并调整音量、静音及窗口/全屏；设置在点击“应用设置”后生效。
合法准备操作会更新检查点；战斗中保存的是开战前准备状态。读取不会恢复战斗中途。开始新局并执行操作可能更新原检查点。
商店“保留至下回合”会保留当前剩余招募位并放弃一次自动刷新，空位不会补充；生效一次或付费刷新后解除。旧版本存档在验证通过后可继续读取。\n存档 session-save.json、备份 session-save.json.bak 和 settings.cfg 保存在系统用户目录，不在 EXE 旁。默认 Windows 位置为 %APPDATA%\\Godot\\app_userdata\\Blue-A - 自走棋\\（尚未在 Windows 实机核验）。

局域网好友房：三人使用同一份完整解压的版本，连接同一 Wi-Fi / 局域网。房主创建房间，把界面上的局域网 IPv4 和端口告知另两人。三人到齐后房主开始本局，另五席为 AI。各自招募、上阵、布阵，三人准备后开战；本轮全部战斗结束、三人确认后进入下一轮。
默认 UDP 端口 27831。若系统询问网络访问，由你确认是否允许此游戏在私人网络通信；本程序不会修改防火墙。访客 Wi-Fi / AP 隔离可能阻止同网设备互通。
非房主掉线后由 AI 接管到本局结束，不恢复真人控制；房主离开会结束整个房间，没有主机迁移。联机局不写入或覆盖单机存档，也不支持保存、读档、暂停或中途加入。设置沿用本机主菜单配置。
联机已做云端回环 ENet 多进程验证；真正三台 Windows 同 Wi-Fi、实际网络延迟及防火墙条件仍需实机验收。

已知边界：非官方个人用途原型，含 14 名角色。部分特效、材质和绑定仍为适配；野宫 EX smoke 的源材质为空，保留 missing_material 已知诊断。普通射击/换弹已接入 96 个原始波形和 28 个 Normal 状态绑定；播放时序、选样和中断为明确的自走棋适配，不宣称原作播放语义还原。Master 输出启用峰值保护（−0.3 dB 目标峰值、0.1 秒释放），不会抬高原始音源增益；存在约 2 毫秒额外混音前瞻延迟。这是本游戏的输出适配，不是原作混音还原。角色台词仍未接入。
本包通过 Linux 云端交叉导出及 PCK 文件/无界面资源检查。Windows EXE 启动、原生渲染、实际可听音频、RTX 4060 性能及真实 release-only 行为尚未验证，不承诺稳定 60FPS。
仅供私人测试；原作素材权利归相应权利人。本包不授予公开发布、商业使用或再分发许可。参见 ASSET-NOTICE.zh-CN.txt 及 Godot 声明。
'''

def execute(args, info):
    output=args.output_root;require_fresh_output(output)
    template_provenance=verify_templates(args.templates)
    if not args.godot.is_file() or sha256(args.godot)!=ENGINE_SHA256:raise ValueError('Linux Godot 4.6.3 binary hash mismatch')
    output.mkdir(parents=True,exist_ok=False)
    stage=output/'staging';checks=output/'checks';logs=output/'logs';packdir=output/'Blue-A-Windows-x86_64'
    for p in (stage,checks,logs,packdir):p.mkdir()
    write_json(checks/'source-commit.json',info)
    archive_commit(args.repo,info['source_commit'],stage)
    # Reuse imported bytes only as an acceleration cache; Godot rechecks inputs.
    cache=args.repo/'.godot/imported'
    if cache.is_dir():
        assert_plain_tree(cache)
        shutil.copytree(cache,stage/'.godot/imported')
    initial_integrity=stage_integrity(stage,info);write_json(checks/'archive-integrity.json',initial_integrity)
    if not initial_integrity['passed']:raise ValueError('Archived files differ from commit blobs')
    manifest=build_manifest(stage)
    for key,count in EXPECTED.items():
        if manifest['summary']['counts'].get(key)!=count:raise ValueError('Current acceptance count changed: '+key)
    manifest_path=checks/'dependency-manifest.json';write_json(manifest_path,manifest)
    overrides=keep_raw_imports(stage,manifest);write_json(checks/'stage-import-overrides.json',overrides)
    preset=(HERE/'export_presets.cfg.in').read_text().replace('@RELEASE_TEMPLATE@',json.dumps(str(args.templates/'windows_release_x86_64.exe'))[1:-1])
    filters=re.search(r'^exclude_filter="(.*)"$',preset,re.M).group(1).split(',')
    collisions=sorted({r['path'] for r in manifest['files'] for f in filters if fnmatch.fnmatchcase(r['path'],f)})
    if collisions:raise ValueError('Excluded required dependencies: '+str(collisions))
    (stage/'export_presets.cfg').write_text(preset)
    source_env=environment(output/'scratch-source');pack_env=environment(output/'scratch-pack')
    empty=output/'isolated-pack';empty.mkdir()
    engine=str(args.godot);harness=str(HERE/'verify_runtime.gd')
    commands=[('import',[engine,'--headless','--path',str(stage),'--editor','--import'],stage,source_env),
       ('source-runtime',[engine,'--headless','--path',str(stage),'--script',harness,'--',str(manifest_path),str(checks/'source-runtime-report.json')],stage,source_env),
       ('export',[engine,'--headless','--path',str(stage),'--export-release','Windows x86_64 Release',str(packdir/'Blue-A.exe')],stage,source_env),
       ('pack-runtime',[engine,'--headless','--path',str(empty),'--main-pack',str(packdir/'Blue-A.pck'),'--script',harness,'--',str(manifest_path),str(checks/'pack-runtime-report.json')],empty,pack_env)]
    write_json(checks/'commands.json',[{'step':name,'argv':cmd,'cwd':str(cwd)} for name,cmd,cwd,_ in commands])
    for name,command,cwd,env in commands:
        print('Running '+name,flush=True)
        run_godot(command,cwd,env,logs/(name+'.log'),args.timeout)
        if name=='source-runtime':
            baseline=json.loads((checks/'source-runtime-report.json').read_text())
            preliminary=compare_runtime_reports(baseline,baseline,nonomi_null_material(stage),[row['character'] for row in manifest['animation_overrides']])
            write_json(checks/'source-acceptance.json',preliminary)
            if not preliminary['passed']:raise ValueError('Source runtime acceptance failed')
        if name=='export':
            if not verify(packdir/'Blue-A.pck',manifest,checks/'pck-report.json'):raise ValueError('PCK contents failed verification')
            for binary in ['Blue-A.exe','Blue-A.console.exe']:
                if pe_machine(packdir/binary)!=0x8664:raise ValueError('Exported PE architecture mismatch')
    source=json.loads((checks/'source-runtime-report.json').read_text());packed=json.loads((checks/'pack-runtime-report.json').read_text())
    parity=compare_runtime_reports(source,packed,nonomi_null_material(stage),[row['character'] for row in manifest['animation_overrides']]);write_json(checks/'runtime-parity-report.json',parity)
    if not parity['passed']:raise ValueError('Source/PCK runtime parity failed')
    integrity=stage_integrity(stage,info,overrides);write_json(checks/'stage-integrity.json',integrity)
    if not integrity['passed']:raise ValueError('Tracked staging files changed unexpectedly')
    assert_plain_tree(stage)
    for name in ['GODOT-LICENSE.txt','GODOT-THIRD-PARTY-NOTICES.txt','ASSET-NOTICE.zh-CN.txt']:
        shutil.copyfile(HERE/'notices'/name,packdir/name)
    (packdir/'README.zh-CN.txt').write_text(readme(info['source_commit'],info['source_commit_epoch']),encoding='utf-8')
    build={'source_commit':info['source_commit'],'source_tree':info['source_tree'],'source_commit_epoch':info['source_commit_epoch'],
       'built_at_utc':datetime.now(timezone.utc).isoformat(),'private_candidate':True,'platform':'Windows x86_64',
       'engine_sha256':ENGINE_SHA256,'templates':template_provenance,'dependency_counts':manifest['summary']['counts'],
       'dependency_manifest_sha256':sha256(manifest_path),'preset_sha256':sha256(stage/'export_presets.cfg'),
       'pipeline_files':{p.name:sha256(p) for p in HERE.iterdir() if p.is_file() and p.suffix in ('.py','.gd','.in')},
       'validation':{'linux_cross_export':True,'pck_hash_resource_checks':True,'source_pack_diagnostics_identical':True,
          'tracked_stage_integrity':True,'windows_exe_executed':False,'native_rendering_verified':False,
          'audible_audio_verified':False,'rtx4060_performance_verified':False,'release_only_behavior_verified':False},
       'known_dependency_diagnostics':parity['known_source_diagnostics'],
       'files':{p.name:{'bytes':p.stat().st_size,'sha256':sha256(p)} for p in sorted(packdir.iterdir())}}
    write_json(packdir/'BUILD-MANIFEST.json',build)
    (packdir/'SHA256SUMS.txt').write_text(''.join(sha256(p)+'  '+p.name+'\n' for p in sorted(packdir.iterdir())))
    zip_path=output/('Blue-A-Windows-x86_64-'+info['source_commit'][:12]+'-candidate.zip')
    make_zip(packdir,zip_path,info['source_commit_epoch'])
    result={'passed':True,'source_commit':info['source_commit'],'zip':str(zip_path),'bytes':zip_path.stat().st_size,'sha256':sha256(zip_path),'checks':str(checks)}
    write_json(output/'BUILD-RESULT.json',result);print(json.dumps(result,indent=2))

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',required=True,type=Path);parser.add_argument('--commit',required=True)
    parser.add_argument('--output-root',required=True,type=Path);parser.add_argument('--templates',required=True,type=Path)
    parser.add_argument('--godot',default=GODOT,type=Path);parser.add_argument('--timeout',default=1800,type=int,help='Per-Godot-process timeout in seconds')
    action=parser.add_mutually_exclusive_group();action.add_argument('--execute',action='store_true');action.add_argument('--dry-run',action='store_true')
    args=parser.parse_args(argv)
    require_fresh_output(args.output_root)
    for name in ('repo','output_root','templates','godot'):setattr(args,name,getattr(args,name).resolve())
    require_fresh_output(args.output_root)
    if args.output_root.is_relative_to(args.repo) or args.output_root.is_relative_to(args.templates):raise ValueError('Output must be outside source repo/template directory')
    if args.timeout<=0:raise ValueError('Timeout must be positive')
    info=source_info(args.repo,args.commit)
    if args.execute:execute(args,info)
    else:print(json.dumps({'mode':'dry-run','source_commit':info['source_commit'],'source_tree':info['source_tree'],
        'archived_roots':ROOTS,'tracked_snapshot_files':len(info['files']),'output_root':str(args.output_root),'templates':str(args.templates),
        'godot':str(args.godot),'godot_executed':False,'output_created':False,'template_validation':'deferred until --execute',
        'steps':['git archive','fresh dependency manifest','narrow Keep File overrides','headless import','source runtime baseline',
                 'Windows release cross-export','PCK hash/member verification','isolated PCK runtime','all diagnostic parity','staging git-blob integrity','private candidate ZIP'],
        'next':'Repeat this exact command with --execute instead of --dry-run after explicit approval'},indent=2))

if __name__=='__main__':
    try:main()
    except (ValueError,FileExistsError,RuntimeError,OSError,subprocess.SubprocessError,AssertionError) as error:
        print('ERROR: '+str(error),file=sys.stderr);sys.exit(1)
