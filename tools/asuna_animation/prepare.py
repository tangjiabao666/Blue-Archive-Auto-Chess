#!/usr/bin/env python3
"""Offline input for compile.gd. Deliberately supports only the audited Asuna GLB.
No runtime glTF reader is shipped or invoked. Accessors preserve float32 times,
values and all source clip extras; the native compiler retains imported paths.
"""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path
PINNED_SOURCE='a874892d8fe4fe952fe4ac0256797c73d82efa432f00eceb3e7e030375c5df07'
PINNED_PAYLOAD='44bcb71a4883c27a223db7181952b336d0ec1dcf802f7186630816afa89ccb01'
MODEL='res://assets/characters/asuna/asuna.glb'
class GLB:
 def __init__(self,raw):
  if len(raw)<28 or struct.unpack_from('<4sII',raw)!=(b'glTF',2,len(raw)):raise ValueError('Invalid GLB header')
  size,kind=struct.unpack_from('<II',raw,12)
  if kind!=0x4e4f534a:raise ValueError('Missing JSON chunk')
  self.doc=json.loads(raw[20:20+size]);offset=20+size
  size,kind=struct.unpack_from('<II',raw,offset)
  if kind!=0x004e4942 or offset+8+size!=len(raw):raise ValueError('Invalid BIN chunk')
  self.blob=raw[offset+8:];self.cache={}
 def access(self,index):
  if index in self.cache:return self.cache[index]
  a=self.doc['accessors'][index];v=self.doc['bufferViews'][a['bufferView']]
  if a['componentType']!=5126 or a['type'] not in ('SCALAR','VEC3','VEC4') or 'sparse' in a or a.get('normalized') or v['buffer']!=0:raise ValueError('Unsupported animation accessor')
  width={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']];stride=v.get('byteStride',width*4);relative=a.get('byteOffset',0);offset=v.get('byteOffset',0)+relative
  if a['count']<1 or stride<width*4 or relative+(a['count']-1)*stride+width*4>v['byteLength']:raise ValueError('Invalid animation accessor bounds')
  values=[list(struct.unpack_from('<'+'f'*width,self.blob,offset+i*stride)) for i in range(a['count'])]
  if any(not math.isfinite(x) for row in values for x in row):raise ValueError('Nonfinite animation accessor')
  if width==1:values=[row[0] for row in values]
  self.cache[index]=values;return values

def build_payload(path,expected_sha=PINNED_SOURCE):
 raw=Path(path).read_bytes();sha=hashlib.sha256(raw).hexdigest()
 if expected_sha!=PINNED_SOURCE or sha!=expected_sha:raise ValueError('Asuna source SHA256 mismatch; re-audit before changing the pinned compiler input')
 g=GLB(raw);names=[n['name'] for n in g.doc['nodes']]
 if len(names)!=len(set(names)):raise ValueError('Ambiguous GLB node names')
 result={'schema_version':1,'source_glb_sha256':sha,'model_path':MODEL,'clips':{},'nodes':{n['name']:{k:n[k] for k in ('translation','rotation','scale')} for n in g.doc['nodes']}}
 for animation in g.doc['animations']:
  clip={'extras':animation['extras'],'channels':{},'length':None}
  if animation['name'] in result['clips']:raise ValueError('Duplicate animation name')
  for c in animation['channels']:
   s=animation['samplers'][c['sampler']];kind=c['target']['path'];name=names[c['target']['node']]
   if s.get('interpolation')!='LINEAR' or kind not in ('translation','rotation','scale'):raise ValueError('Unsupported interpolation/property')
   times=g.access(s['input']);values=g.access(s['output'])
   if times[0]!=0 or len(times)!=len(values) or not all(a<b for a,b in zip(times,times[1:])):raise ValueError('Invalid source key coordinates')
   if kind=='rotation' and any(abs(sum(x*x for x in q)**.5-1)>1e-6 for q in values):raise ValueError('Nonunit source quaternion')
   if clip['length'] is not None and clip['length']!=times[-1]:raise ValueError('Inconsistent source duration')
   clip['length']=times[-1];key=name+'|'+kind
   if key in clip['channels']:raise ValueError('Duplicate channel')
   clip['channels'][key]={'times':times,'values':values,'node':name,'kind':kind}
  result['clips'][animation['name']]=clip
 if len(result['clips'])!=12 or sum(len(c['channels']) for c in result['clips'].values())!=4340:raise ValueError('Source topology differs from audited Asuna input')
 return result
def payload_bytes(payload):
 encoded=(json.dumps(payload,separators=(',',':'))+'\n').encode('utf-8')
 if hashlib.sha256(encoded).hexdigest()!=PINNED_PAYLOAD:raise ValueError('Prepared payload SHA256 differs from audited source; re-audit before changing the input contract')
 return encoded

if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--glb',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
 args=parser.parse_args();payload=build_payload(args.glb);args.output.write_bytes(payload_bytes(payload))
 print('Prepared 12 clips / 4340 channels / 302315 original keys:',args.output)
