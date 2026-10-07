extends RefCounted
## Translates unchanged source skill shapes/contact schedules into runtime volumes.
static func build(data:Dictionary)->Dictionary:
 var u:Dictionary=data.source;var source:Dictionary=data.source_skill;var context:Dictionary=data.context
 var kind:String=str(source.get('kind','normal'))
 if data.component=='direct':return {}
 if kind in ['drone_damage','single_target_burst']:return {}
 var shapes:Array=source.get('shapeSource',[])
 if shapes.is_empty():return {}
 var shape:Dictionary=shapes[0]
 if shape.Type not in ['Circle','Fan','Obb']:return {}
 var origin:Vector2=context.get('origin',u.cell);var point:Vector2=context.get('target_cell',u.cell)
 var direction:Vector2=origin.direction_to(point)
 if direction==Vector2.ZERO:direction=Vector2.UP if u.team==0 else Vector2.DOWN
 var result:Dictionary={'source':u.id,'team':u.team,'ability':data.ability,'cast_start_tick':int(context.get('cast_start_tick',data.tick)),
  'origin':context.get('damage_origin',origin),'direction':direction,'centers':[point],'radius':float(shape.get('Radius',1))/data.scale,
  'width':float(shape.get('Width',1))/data.scale,'length':float(shape.get('Height',1))/data.scale,'degrees':float(shape.get('Degree',360)),
  'shape':'circle' if shape.Type=='Circle' else 'fan' if shape.Type=='Fan' else 'line','contact_policy':'lob' if shape.Type=='Circle' else 'direct','impacts':[]}
 if kind=='three_shot_target_then_rear_fan':
  result.shape='target_fan';result.fan_origin=point;result.primary_target=int(context.get('target_id',-1))
 if kind in ['line_damage_with_target_falloff','charge_scaled_line_damage']:result.contact_policy='penetrating'
 if kind=='line_damage_with_target_falloff':result.falloff={'step':source.damageReductionPerSubsequentTarget,'minimum':source.minimumDamageFraction}
 if context.has('mine_id'):result.emitted=true
 var weights:Array=data.damage.hitWeights
 var first:int=maxi(1,int(data.duration*0.2)) if data.first_offset<0 else maxi(1,data.first_offset)
 var last:int=maxi(first,int(data.duration*0.85))
 for index in range(weights.size()):
  var offset:int=first if weights.size()==1 else int(round(lerpf(first,last,float(index)/(weights.size()-1))))
  if data.contact_ticks.size()==weights.size():offset=data.contact_ticks[index]
  offset=maxi(offset,data.lower_bound)
  var hit:Dictionary={'source':u.id,'due':data.tick+offset,'effect':'damage','atk_ratio':data.damage.totalAtkRatio*weights[index],
   'can_crit':data.damage.get('canCrit',true),'kind':'attack' if data.ability=='normal' else 'skill','ability':data.ability,'component':data.component,
   'hit_index':index,'hit_count':weights.size(),'origin':context.get('damage_origin',u.cell),'cast_start_tick':result.cast_start_tick,'cast_target_cell':point,
   'timing_adaptation':'source_visual_contact' if data.contact_ticks.size()==weights.size() else 'not_before_hand_prop_end_adaptation' if data.lower_bound>0 else 'legacy_cast_dispatch'}
  if context.has('mine_id'):hit.mine_id=context.mine_id
  if data.effect_skill.get('knockbackPerHit',false):hit.knockback=data.effect_skill.knockbackDisplayedSourceUnits/data.scale
  if data.effect_skill.has('stunSeconds') and (not data.final_stun or index==weights.size()-1):hit.stun_seconds=data.effect_skill.stunSeconds
  result.impacts.append({'due':hit.due,'hit':hit})
 return result
