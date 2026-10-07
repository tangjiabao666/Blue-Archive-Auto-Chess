import argparse, hashlib, json, struct
from pathlib import Path

def inspect_pack(path):
    size = path.stat().st_size
    entries = []
    with path.open('rb') as f:
        def u(fmt):
            n=struct.calcsize(fmt); b=f.read(n)
            assert len(b)==n, 'truncated pack'
            return struct.unpack(fmt,b)
        assert f.read(4)==b'GDPC', 'bad magic'
        version,major,minor,patch,flags=u('<5I')
        assert version in (2,3), version
        assert not flags&1, 'encrypted directory unsupported'
        base,=u('<Q')
        if version==3:
            directory,=u('<Q'); f.seek(directory)
        else:
            f.seek(64,1)
        count,=u('<I'); assert 0<count<100000
        for _ in range(count):
            length,=u('<I'); assert length<65536
            name=f.read(length).rstrip(b'\0').decode('utf-8').removeprefix('res://')
            offset,length=u('<QQ'); md5=f.read(16); eflags,=u('<I')
            assert eflags==0, (name,eflags)
            assert 0<=base+offset<=size and length<=size-(base+offset),(name,offset,length,size)
            entries.append({'path':name,'offset':base+offset,'bytes':length,'md5':md5.hex()})
        assert len({x['path'] for x in entries})==count,'duplicate pack names'
        for entry in entries:
            name=entry['path']
            assert name and not name.startswith('/') and '\\' not in name and ':' not in name and '..' not in name.split('/'), 'unsafe pack member '+name
        for e in entries:
            f.seek(e['offset']);data=f.read(e['bytes'])
            assert hashlib.md5(data).hexdigest()==e['md5'],'pack MD5 mismatch '+e['path']
            e['sha256']=hashlib.sha256(data).hexdigest()
    return {'format':version,'engine':[major,minor,patch],'pack_bytes':size,'entries':entries}

def verify(path,manifest,output):
    report=inspect_pack(path); table={e['path']:e for e in report['entries']}
    raw_categories={'runtime_json','vfx_texture_json','vfx_texture_png','mesh_raw','animation_libraries','animation_library_manifests'}
    required={e['path']:e for e in manifest['files'] if e['category'] in raw_categories}
    missing=[p for p in required if p not in table]
    mismatched=[p for p,e in required.items() if p in table and table[p]['sha256']!=e['sha256']]
    forbidden=[p for p in table if p.startswith(('tests/','evidence/','docs/','tools/','.git/')) or '/source_objects/' in p or '/source_materials/' in p or p.endswith(('.py','.pyc','.md','.log','.bundle','.unity3d')) or 'session-save' in p or p.endswith('settings.cfg')]
    extraction=manifest['excluded_effect_source_json']
    leaked=[p for p in extraction if p in table]
    missing_main=[p for p in ['project.binary','game.tscn'] if p not in table and p+'.remap' not in table]
    ordinary=[e['path'] for e in manifest['files'] if e['category']=='ordinary_audio_streams']
    ordinary_missing=[p for p in ordinary if not any(p+suffix in table for suffix in ('','.import','.remap'))]
    report.update({'missing_main_resources':missing_main,'required_raw_count':len(required),'raw_missing':missing,'raw_mismatched':mismatched,'forbidden_members':forbidden,'leaked_extraction_json':leaked,'ordinary_audio_resource_count':len(ordinary),'ordinary_audio_missing':ordinary_missing,'all_members_md5_verified':True,'passed':not (missing or mismatched or forbidden or leaked or missing_main or ordinary_missing)})
    output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='entries'},indent=2))
    return report['passed']

if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('pack',type=Path);a.add_argument('manifest',type=Path);a.add_argument('output',type=Path);args=a.parse_args()
    raise SystemExit(0 if verify(args.pack,json.loads(args.manifest.read_text()),args.output) else 1)
