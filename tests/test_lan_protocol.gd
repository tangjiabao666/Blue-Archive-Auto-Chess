extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 ck(ResourceLoader.exists('res://core/lan/protocol.gd'),'LAN protocol exists')
 if failures:quit(1);return
 var p=load('res://core/lan/protocol.gd')
 var hello:Dictionary={'protocol':1,'type':'hello','epoch':0,'seq':1,'payload':{'build':p.BUILD_ID,'nickname':'朋友甲'}}
 var bytes:PackedByteArray=p.encode(hello);ck(not bytes.is_empty(),'legal hello encodes')
 var result:Dictionary=p.decode(bytes);ck(result.ok and result.message==hello,'wire roundtrip canonicalizes integer fields')
 for bad in [{},[],true,{'protocol':true,'type':'hello','epoch':0,'seq':1,'payload':{}},{'protocol':1,'type':'eval','epoch':0,'seq':1,'payload':{}},{'protocol':1,'type':'hello','epoch':-1,'seq':1,'payload':{}},{'protocol':1,'type':'hello','epoch':0,'seq':1.5,'payload':{}}]:
  ck(not p.decode(JSON.stringify(bad).to_utf8_buffer()).ok,'malformed envelope rejected')
 ck(not p.decode('x'.repeat(65537).to_utf8_buffer()).ok,'absolute packet budget enforced')
 var big:Dictionary=hello.duplicate(true);big.payload.nickname='x'.repeat(5000);ck(p.encode(big).is_empty(),'client control packet budget enforced')
 ck(p.is_lan_address('192.168.1.23') and p.is_lan_address('10.0.0.2') and p.is_lan_address('172.16.0.2') and p.is_lan_address('127.0.0.1'),'private and QA loopback addresses supported')
 for ip in ['8.8.8.8','example.com','192.168.1.999','172.32.0.1','1.2.3','0.0.0.0']:ck(not p.is_lan_address(ip),'nonLAN or malformed address rejected '+ip)
 print('LAN_PROTOCOL checks=',checks,' failures=',failures);quit(1 if failures else 0)
