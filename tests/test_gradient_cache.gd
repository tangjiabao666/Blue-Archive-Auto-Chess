extends SceneTree
var failures:=0
var checks:=0
var sampler
func ck(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;printerr(message)
func _initialize():
	sampler=load("res://vfx/native_curves.gd").new()
	ck(sampler.has_method("clear_gradient_cache") and sampler.has_method("gradient_cache_stats"),"gradient cache exposes bounded reset/statistics")
	if failures:quit(1);return
	sampler.clear_gradient_cache()
	var gradients:Array=[]
	for key in ["shiroko","hoshino","hina","aru","yuuka","aris","serika"]:
		_collect(load("res://vfx/native_source.gd").read_json("res://data/effects/"+key+"/visual-templates.json"),gradients)
	for g in gradients:
		for t in [-0.1,0.0,0.13,0.35,0.5,0.999,1.0,1.1]:
			ck(sampler.gradient(g,t)==reference(g,t),"native gradient exact parity")
	var g={"key0":{"r":2.0,"g":0.5,"b":3.0,"a":0.25},"key1":{"r":0.25,"g":4.0,"b":0.1,"a":1.0},"m_NumColorKeys":2,"m_NumAlphaKeys":2,"ctime0":0,"ctime1":65535,"atime0":0,"atime1":65535,"m_Mode":0}
	sampler.clear_gradient_cache()
	for i in range(100):ck(sampler.gradient(g,i/100.0)==reference(g,i/100.0),"repeated HDR gradient parity")
	ck(sampler.gradient_cache_stats().compilations==1,"repeated samples compile keys once")
	g.key1.r=0.75
	ck(sampler.gradient(g,0.8)==reference(g,0.8),"mutating input cannot use stale cache")
	g.m_Mode=1
	for t in [0.1,0.9,1.0]:ck(sampler.gradient(g,t)==reference(g,t),"fixed gradient exact key boundaries")
	for i in range(700):
		g.key0.r=float(i);sampler.gradient(g,0.2)
	ck(sampler.gradient_cache_stats().entries<=256,"gradient cache is bounded")
	sampler.clear_gradient_cache();ck(sampler.gradient_cache_stats().entries==0,"clear releases cached recipes")
	print("GRADIENT CACHE CHECKS=",checks," FAILURES=",failures);quit(1 if failures else 0)
func _collect(v:Variant,out:Array):
	if v is Dictionary:
		if v.has("m_NumColorKeys"):out.append(v)
		for key in v:_collect(v[key],out)
	elif v is Array:
		for item in v:_collect(item,out)
func reference(g:Dictionary,t:float)->Color:
	if g.is_empty():return Color.WHITE
	var result:Color=sampler.color_value(g.get("key0",{}))
	for alpha in [false,true]:
		var count:int=int(g.get("m_NumAlphaKeys" if alpha else "m_NumColorKeys",0))
		if count<=0:continue
		var value:Color=sampler.color_value(g.get("key%d"%(count-1),{}))
		var prefix:String="atime" if alpha else "ctime"
		if t<=float(g.get(prefix+"0",0))/65535.0:value=sampler.color_value(g.get("key0",{}))
		else:
			for i in range(1,count):
				var end:float=float(g.get(prefix+str(i),65535))/65535.0
				if t>end:continue
				var start:float=float(g.get(prefix+str(i-1),0))/65535.0
				var a:Color=sampler.color_value(g.get("key%d"%(i-1),{}));var b:Color=sampler.color_value(g.get("key%d"%i,{}))
				value=(b if t>=end else a) if int(g.get("m_Mode",0))==1 else a.lerp(b,clampf((t-start)/maxf(end-start,0.000001),0,1))
				break
		if alpha:result.a=value.a
		else:result.r=value.r;result.g=value.g;result.b=value.b
	return result
