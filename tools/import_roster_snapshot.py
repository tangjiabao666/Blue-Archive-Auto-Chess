#!/usr/bin/env python3
"""Incrementally import verified native character snapshots.

Two-pass use:
  python tools/import_roster_snapshot.py --source SNAPSHOT --root PROJECT
  godot --headless --path PROJECT --editor --import
  python tools/import_roster_snapshot.py --source SNAPSHOT --root PROJECT --configure-only
  godot --headless --path PROJECT --editor --import

Only incoming character IDs are changed. Existing unrelated profiles, files and
Godot import settings are preserved. This command does not activate the roster.
"""
from pathlib import Path
import argparse,hashlib,json,math,re,shutil,sys,tempfile

NAMES={'shiroko':'白子','hoshino':'星野','hina':'日奈','aru':'阿露','yuuka':'优香','aris':'爱丽丝','serina':'芹奈','serika':'芹香','iori':'伊织','tsubaki':'椿','nonomi':'野宫','mutsuki':'睦月','haruna':'晴奈','koharu':'小春'}

def read_json(path):
    if not path.is_file():raise ValueError('Missing input file: '+str(path))
    try:return json.loads(path.read_text(encoding='utf-8'))
    except (ValueError,OSError) as error:raise ValueError('Invalid JSON input '+str(path)+': '+str(error)) from error

def source_path(value,base):
    if not isinstance(value,str) or not value:raise ValueError('Required source path is empty')
    path=Path(value)
    return path if path.is_absolute() else base/path

def valid_id(value):
    if not isinstance(value,str) or not re.fullmatch(r'[a-z0-9_]+',value):raise ValueError('Unsafe character id: '+repr(value))
    return value

def relative_filename(value):
    if not isinstance(value,str) or not value:raise ValueError('Missing texture filename')
    path=Path(value)
    if path.is_absolute() or '..' in path.parts or '\\' in value:raise ValueError('Unsafe texture filename: '+value)
    return path

def load_profiles(source):
    path=source if source.is_file() else source/'export-profiles.json'
    document=read_json(path);profiles=document.get('profiles')
    if not isinstance(profiles,list) or not profiles:raise ValueError('Snapshot profiles must be a nonempty list')
    seen=set()
    for profile in profiles:
        if not isinstance(profile,dict):raise ValueError('Invalid profile entry')
        key=valid_id(profile.get('id'))
        if key in seen:raise ValueError('Duplicate incoming profile: '+key)
        seen.add(key)
        fps=profile.get('required_godot_animation_fps',60)
        if not isinstance(fps,(int,float)) or not math.isfinite(fps) or fps<=0:raise ValueError('Invalid import FPS for '+key)
    return profiles,path.parent

def resolve_anchors(profile, model):
    """Resolve symbolic GLB anchors into the runtime socket contract, without changing source bytes."""
    anchors = profile.get('anchors', [])
    if not isinstance(anchors, list): raise ValueError('Invalid source anchors list')
    if not anchors: return []
    if all(isinstance(anchor, str) for anchor in anchors):
        import struct
        raw = model.read_bytes()
        try:
            magic, version, total, size, kind = struct.unpack_from('<4sIIII', raw)
            if magic != b'glTF' or version != 2 or total != len(raw) or kind != 0x4e4f534a or 20 + size > len(raw):
                raise ValueError('Invalid GLB anchor container')
            document = json.loads(raw[20:20 + size])
            nodes = document['nodes']
            if not isinstance(nodes, list) or not all(isinstance(node, dict) for node in nodes):
                raise ValueError('Invalid GLB anchor nodes')
        except (KeyError, TypeError, struct.error, UnicodeError, json.JSONDecodeError) as error:
            raise ValueError('Cannot decode GLB source anchors') from error
        parents = {}
        for index, node in enumerate(nodes):
            children = node.get('children', [])
            if not isinstance(children, list): raise ValueError('Invalid source anchor hierarchy')
            for child in children:
                if type(child) is not int or not 0 <= child < len(nodes) or child in parents:
                    raise ValueError('Ambiguous or invalid source anchor hierarchy')
                parents[child] = index
        resolved = []
        for name in anchors:
            matches = [i for i, node in enumerate(nodes) if node.get('name') == name]
            if len(matches) != 1: raise ValueError('Missing or ambiguous source anchor: ' + name)
            index = matches[0]; node = nodes[index]
            if 'matrix' in node: raise ValueError('Matrix source anchor needs explicit reviewed TRS: ' + name)
            path = []; visited = set(); cursor = index
            while cursor is not None:
                if cursor in visited: raise ValueError('Cyclic source anchor hierarchy')
                visited.add(cursor); part = nodes[cursor].get('name')
                if not isinstance(part, str) or not part or '/' in part or part in ('.', '..'):
                    raise ValueError('Invalid source anchor path component')
                path.append(part); cursor = parents.get(cursor)
            resolved.append({'name': name, 'path': '/'.join(reversed(path)),
                'local_translation': node.get('translation', [0, 0, 0]),
                'local_rotation': node.get('rotation', [0, 0, 0, 1]),
                'local_scale': node.get('scale', [1, 1, 1])})
        anchors = resolved
    elif not all(isinstance(anchor, dict) for anchor in anchors):
        raise ValueError('Mixed or malformed source anchor records')
    names = set()
    for anchor in anchors:
        name = anchor.get('name'); path = anchor.get('path')
        if not isinstance(name, str) or not name or name in names or not isinstance(path, str):
            raise ValueError('Missing or duplicate source anchor identity')
        names.add(name); parts = path.split('/')
        if len(parts) < 2 or parts[-1] != name or any(not part or part in ('.', '..') for part in parts):
            raise ValueError('Invalid source anchor path: ' + name)
        for field, length, default in [('local_translation', 3, None), ('local_rotation', 4, None), ('local_scale', 3, [1, 1, 1])]:
            value = anchor.get(field, default)
            if not isinstance(value, list) or len(value) != length or any(type(v) not in (int, float) or not math.isfinite(v) for v in value):
                raise ValueError('Invalid source anchor ' + field + ': ' + name)
        if abs(sum(v * v for v in anchor['local_rotation']) - 1) > 1e-5:
            raise ValueError('Non-unit source anchor rotation: ' + name)
        if name == profile.get('muzzle_anchor') and anchor.get('local_scale', [1, 1, 1]) != [1, 1, 1]:
            raise ValueError('Scaled muzzle source anchor is not supported: ' + name)
    return anchors

def validate_snapshot(profiles,source):
    """Read and validate every input before creating or copying target assets."""
    validated=[]
    for profile in profiles:
        key=profile['id'];model=source_path(profile.get('model'),source)
        if not model.is_file():raise ValueError('Missing input model: '+str(model))
        with model.open('rb') as stream:
            if stream.read(4)!=b'glTF':raise ValueError('Input model is not GLB: '+str(model))
        texture_manifest=source_path(profile.get('texture_manifest'),source);textures=read_json(texture_manifest).get('textures')
        if not isinstance(textures,list):raise ValueError('Invalid textures list: '+str(texture_manifest))
        texture_files=[]
        for texture in textures:
            filename=relative_filename(texture.get('filename'));path=texture_manifest.parent/filename
            if not path.is_file():raise ValueError('Missing input texture: '+str(path))
            texture_files.append((texture,filename,path))
        material_folder=source_path(profile.get('material_folder'),source)
        if not material_folder.is_dir():raise ValueError('Missing input material folder: '+str(material_folder))
        materials=[]
        for material_file in sorted(material_folder.glob('*.json')):
            material=read_json(material_file)
            try:
                props=material['m_SavedProperties'];material['m_Name'];material['m_Shader']['m_PathID']
                for slot,value in props['m_TexEnvs']:
                    value['m_Texture']['m_PathID'];value['m_Scale']['x'];value['m_Scale']['y'];value['m_Offset']['x'];value['m_Offset']['y']
                dict(props['m_Floats']);dict(props['m_Colors'])
            except (KeyError,TypeError,ValueError) as error:raise ValueError('Invalid input material: '+str(material_file)) from error
            materials.append(material)
        if not materials:raise ValueError('No source materials: '+str(material_folder))
        manifest=read_json(source_path(profile.get('source_manifest'),source))
        if not isinstance(profile.get('clips'),dict):raise ValueError('Invalid clips for '+key)
        for field in ('model_scale','model_yaw_radians'):
            value=profile.get(field)
            if not isinstance(value,(int,float)) or not math.isfinite(value):raise ValueError('Invalid '+field+' for '+key)
        validated.append({'profile':profile,'model':model,'textures':texture_files,'materials':materials,'manifest':manifest,'anchors':resolve_anchors(profile,model)})
    return validated

def build_presentation(item,root):
    profile=item['profile'];key=profile['id'];by_id={str(t['path_id']):(t,path) for t,filename,path in item['textures']};bindings=[]
    for material in item['materials']:
        props=material['m_SavedProperties'];textures={};vectors={}
        for slot,value in props['m_TexEnvs']:
            entry=by_id.get(str(value['m_Texture']['m_PathID']))
            if entry:textures[slot]=f'res://assets/characters/{key}/'+entry[0]['filename']
            elif slot=='_MouthTileTex':textures[slot]='res://assets/native/Character_Mouth.png'
            vectors[slot]=[value['m_Scale']['x'],value['m_Scale']['y'],value['m_Offset']['x'],value['m_Offset']['y']]
        bindings.append({'name':material['m_Name'],'textures':textures,'texture_st':vectors,'floats':dict(props['m_Floats']),'colors':dict(props['m_Colors']),'shader_id':str(material['m_Shader']['m_PathID']),'keywords':material.get('m_ValidKeywords',[])})
    original_clips=profile['clips'];clips={('walk' if k=='move' else 'attack_fire' if k=='attack' else k):(v or '') for k,v in original_clips.items()}
    # An explicit empty/null basic means "none" and must not be guessed over.
    if 'basic' not in original_clips:
        candidates=[a['name'] for a in item['manifest'].get('animations',[]) if 'Public01' in a.get('name','')]
        clips['basic']=candidates[0] if candidates else ''
    result={'display_name':NAMES.get(key,profile.get('display_name',key)),'model_path':f'res://assets/characters/{key}/{key}.glb','model_scale':profile['model_scale'],'model_yaw':profile['model_yaw_radians'],'normalize_durations':False,'clips':clips,'materials':bindings,'muzzle_anchor':profile.get('muzzle_anchor') or '','anchors':item['anchors'],'fire_contact_offset':0.0,'source_glb_sha256':hashlib.sha256(item['model'].read_bytes()).hexdigest(),'source_sampling_hz':profile.get('required_godot_animation_fps',item['manifest'].get('animation_sampling_hz',60)),'source_limitations':item['manifest'].get('limitations',[]),'initial_hidden_nodes':[n['node_name'] for n in profile.get('source_initial_visibility',[]) if not n['unity_gameobject_active'] or not n['unity_renderer_enabled']],'legacy_fx_filter':False,'native_burst_cycle':True,'required_godot_animation_fps':profile.get('required_godot_animation_fps',60)}
    timeline_path=root/'data/effects/battle-events-compact.json'
    if timeline_path.is_file():
        timeline=read_json(timeline_path);windows={}
        for track in timeline.get('characters',{}).get(key,{}).get('timelines',[]):
            kind=track.get('kind')
            if kind not in ('ex','basic'):continue
            for event in track.get('events',[]):
                if event.get('kind')=='animation' and event.get('label')==clips.get(kind):
                    windows[kind]={k:event[k] for k in ('start','duration','clipIn','speed') if k in event}
        if windows:result['action_windows']=windows
    for field in ('action_windows','activation_windows'):
        if field in profile:result[field]=profile[field]
    return result

def _quoted_end(text,start):
    i=start+1
    while i<len(text):
        if text[i]=='\\':i+=2;continue
        if text[i]=='"':return i+1
        i+=1
    raise ValueError('Unterminated quoted Godot value')

def _value_end(text,start):
    stack=[];i=start
    while i<len(text):
        char=text[i]
        if char=='"':i=_quoted_end(text,i);continue
        if char in '{[(':stack.append(char)
        elif char in '}])':
            if not stack:return i
            stack.pop()
        elif char==',' and not stack:return i
        i+=1
    return i

def _dict_entries(text):
    if not text.strip().startswith('{'):raise ValueError('Expected Godot dictionary')
    entries={};i=text.index('{')+1
    while i<len(text):
        while i<len(text) and (text[i].isspace() or text[i]==','):i+=1
        if i>=len(text) or text[i]=='}':break
        if text[i]=='&':i+=1
        if text[i]!='"':raise ValueError('Unsupported Godot dictionary key; refusing destructive rewrite')
        end=_quoted_end(text,i);key=json.loads(text[i:end]);i=end
        while i<len(text) and text[i].isspace():i+=1
        if text[i]!=':':raise ValueError('Invalid Godot dictionary separator')
        i+=1
        while i<len(text) and text[i].isspace():i+=1
        end=_value_end(text,i);entries[key]=(i,end);i=end
    return entries

def _dict_get(text,key,default='{}'):
    entry=_dict_entries(text).get(key)
    return text[entry[0]:entry[1]].strip() if entry else default

def _dict_set(text,key,value):
    entry=_dict_entries(text).get(key)
    if entry:
        previous=text[entry[0]:entry[1]];trailing=previous[len(previous.rstrip()):]
        return text[:entry[0]]+value+trailing+text[entry[1]:]
    end=text.rfind('}');inner=text[text.index('{')+1:end].strip();separator=',\n' if inner and not inner.endswith(',') else '\n'
    return text[:end].rstrip()+separator+json.dumps(key)+': '+value+'\n'+text[end:]

def patched_import_text(text,fps):
    if re.search(r'^animation/fps=',text,re.M):text=re.sub(r'^animation/fps=.*$',f'animation/fps={fps:g}',text,flags=re.M)
    else:
        if '[params]' not in text:raise ValueError('Godot import file has no params section')
        text=text.replace('[params]','[params]\nanimation/fps='+format(fps,'g'),1)
    match=re.search(r'^_subresources\s*=\s*',text,re.M)
    if match:
        start=match.end()
        if text[start:start+1]!='{':raise ValueError('Unsupported Godot _subresources value')
        # _value_end scans the whole outer dictionary until the next top-level token;
        # find its matching close explicitly so following INI lines remain untouched.
        i=start;depth=0
        while i<len(text):
            if text[i]=='"':i=_quoted_end(text,i);continue
            if text[i]=='{':depth+=1
            elif text[i]=='}':
                depth-=1
                if depth==0:break
            i+=1
        if depth:raise ValueError('Unterminated Godot subresources dictionary')
        end=i+1;sub=text[start:end]
    else:start=end=len(text);sub='{}'
    nodes=_dict_get(sub,'nodes');animation=_dict_get(nodes,'PATH:AnimationPlayer');animation=_dict_set(animation,'optimizer/enabled','false');nodes=_dict_set(nodes,'PATH:AnimationPlayer',animation);sub=_dict_set(sub,'nodes',nodes)
    if match:return text[:start]+sub+text[end:]
    return text.rstrip()+'\n_subresources='+sub+'\n'

DATA_TEXTURE_SLOTS = frozenset(('_HairSpecTex', '_MaskTex', '_SourceTex'))


def project_resource_path(root, resource):
    """Accept only canonical project paths, including their resolved symlink targets."""
    if not isinstance(resource, str) or not resource.startswith('res://'):
        raise ValueError('Invalid project resource path: ' + repr(resource))
    relative = resource[len('res://'):]
    if ('\\' in relative or any(ord(char) < 32 for char in relative)
            or any(part in ('', '.', '..') for part in relative.split('/'))
            or Path(relative).is_absolute()):
        raise ValueError('Unsafe project resource path: ' + repr(resource))
    path = root / relative
    try:
        path.resolve().relative_to(root.resolve())
    except (ValueError, RuntimeError) as error:
        raise ValueError('Project resource escapes project root: ' + resource) from error
    return path


def data_texture_paths(root, presentation, key):
    if not isinstance(presentation, dict) or not isinstance(presentation.get('materials'), list):
        raise ValueError('Invalid presentation materials for ' + key)
    data_paths = set()
    color_paths = set()
    for material in presentation['materials']:
        if not isinstance(material, dict) or not isinstance(material.get('textures'), dict):
            raise ValueError('Invalid presentation texture bindings for ' + key)
        for slot, resource in material['textures'].items():
            path = project_resource_path(root, resource)
            if slot in DATA_TEXTURE_SLOTS:
                data_paths.add(path)
            elif slot == '_MainTex':
                color_paths.add(path.resolve())
    if any(path.resolve() in color_paths for path in data_paths):
        raise ValueError('Texture is bound as both a data map and _MainTex for ' + key)
    return sorted(data_paths)


def patched_data_import_text(text):
    """Change the one data-sensitive option without normalizing any other bytes."""
    lines = text.splitlines(keepends=True)
    params = []
    options = []
    section = None
    option = 'process/fix_alpha_border'
    for index, line in enumerate(lines):
        content = line.rstrip('\r\n')
        header = re.fullmatch(r'\s*\[([^]\r\n]+)\]\s*(?:;.*)?', content)
        if content.lstrip().startswith('[') and not header:
            raise ValueError('Invalid data texture import section: ' + content)
        if header:
            section = header[1]
            if section == 'params':
                params.append(index)
        if re.match(r'\s*' + re.escape(option) + r'(?:\s|=|$)', content):
            match = re.fullmatch(r'(\s*' + re.escape(option) + r'\s*=\s*)(true|false)(\s*(?:;.*)?)', content)
            if section != 'params' or not match:
                raise ValueError('Invalid data texture import option: ' + option)
            options.append((index, match))
    if len(params) != 1:
        raise ValueError('Data texture import must have exactly one params section')
    if len(options) > 1:
        raise ValueError('Duplicate data texture import option: ' + option)
    if options:
        index, match = options[0]
        line = lines[index]
        lines[index] = line[:match.start(2)] + 'false' + line[match.end(2):]
    else:
        index = params[0]
        newline = '\r\n' if lines[index].endswith('\r\n') else '\n'
        if not lines[index].endswith('\n'):
            lines[index] += newline
        lines.insert(index + 1, option + '=false' + newline)
    return ''.join(lines)


def import_configuration_plan(root, profiles, presentations):
    """Validate all selected paths and configurations before any write is allowed."""
    if not isinstance(presentations, dict):
        raise ValueError('Existing presentations must be an object')
    updates = {}
    pending = []
    missing = []
    for profile in profiles:
        key = valid_id(profile['id'])
        data_paths = data_texture_paths(root, presentations.get(key), key)
        model_resource = f'res://assets/characters/{key}/{key}.glb'
        project_resource_path(root, model_resource)
        model_import = project_resource_path(root, model_resource + '.import')
        configurations = [(model_import, False)]
        for texture in data_paths:
            resource = 'res://' + texture.relative_to(root).as_posix() + '.import'
            configurations.append((project_resource_path(root, resource), True))
        for path, is_data_map in configurations:
            if not path.is_file():
                if path.exists():
                    raise ValueError('Godot import configuration is not a file: ' + str(path))
                if key not in pending:
                    pending.append(key)
                missing.append(str(path.relative_to(root)))
                continue
            text = path.read_bytes().decode('utf-8')
            try:
                updated = (patched_data_import_text(text) if is_data_map else
                           patched_import_text(text, float(profile.get('required_godot_animation_fps', 60))))
            except (ValueError, IndexError) as error:
                raise ValueError('Invalid Godot import configuration ' + str(path) + ': ' + str(error)) from error
            updates[path] = updated
    return updates, pending, missing


def apply_import_configuration(plan, require_all=False):
    updates, pending, missing = plan
    if pending:
        if require_all:
            raise ValueError('Godot import files not generated: ' + ', '.join(missing)
                             + '. Run Godot --editor --import, then --configure-only.')
        # Do not configure GLBs alone when any selected data map is still pending.
        return pending
    for path, text in updates.items():
        encoded = text.encode('utf-8')
        if path.read_bytes() != encoded:
            path.write_bytes(encoded)
    return pending


def configure_imports(root, profiles, require_all=False):
    presentations = read_json(root / 'data/character-presentations.json')
    return apply_import_configuration(import_configuration_plan(root, profiles, presentations), require_all)

def atomic_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile('w',encoding='utf-8',dir=path.parent,delete=False,prefix=path.name+'.',suffix='.tmp') as stream:
        temporary=Path(stream.name);json.dump(value,stream,ensure_ascii=False,indent=2);stream.write('\n')
    temporary.replace(path)

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source',required=True,type=Path,help='Snapshot directory or export-profiles.json')
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1],help='Target Godot project root')
    parser.add_argument('--configure-only',action='store_true',help='Do not copy assets or edit profiles; patch only selected Godot import files after the first engine import')
    args=parser.parse_args(argv)
    try:
        profiles,source=load_profiles(args.source.resolve());root=args.root.resolve()
        if args.configure_only:
            configure_imports(root,profiles,require_all=True);print('Configured import settings for '+', '.join(p['id'] for p in profiles));return 0
        items=validate_snapshot(profiles,source);presentation_path=root/'data/character-presentations.json'
        existing=read_json(presentation_path) if presentation_path.exists() else {}
        if not isinstance(existing,dict):raise ValueError('Existing presentations must be an object')
        incoming={item['profile']['id']:build_presentation(item,root) for item in items}
        # Preflight every selected GLB/data-map configuration before copying assets.
        configuration_plan=import_configuration_plan(root,profiles,incoming)
        for item in items:
            key=item['profile']['id']
            for texture,filename,path in item['textures']:
                project_resource_path(root,f'res://assets/characters/{key}/'+filename.as_posix())
        result=dict(existing)
        for item in items:
            key=item['profile']['id'];destination=root/'assets/characters'/key;destination.mkdir(parents=True,exist_ok=True)
            shutil.copy2(item['model'],destination/(key+'.glb'))
            for texture,filename,path in item['textures']:
                target=destination/filename;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
            result[key]={**existing.get(key,{}),**incoming[key]}
        atomic_json(presentation_path,result);pending=apply_import_configuration(configuration_plan)
        print(json.dumps({'imported':[p['id'] for p in profiles],'preserved_unrelated_profiles':len(set(existing)-set(incoming)),'pending_godot_import_configuration':pending,'next_step':'Run Godot --editor --import; then repeat with --configure-only; then reimport' if pending else 'Reimport changed assets in Godot'},ensure_ascii=False))
        return 0
    except (ValueError,OSError,KeyError,TypeError) as error:
        print('Snapshot import failed: '+str(error),file=sys.stderr);return 2
if __name__=='__main__':raise SystemExit(main())
