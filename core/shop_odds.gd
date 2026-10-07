extends RefCounted
## Autochess economy adaptation. Source skill coefficients are not modified.
const LEVEL_WEIGHTS={4:{1:8,2:44,3:36,4:12},5:{1:8,2:36,3:36,4:20},6:{1:8,2:28,3:36,4:28}}
static func supports(catalog:Array)->bool:
 for entry in catalog:
  if int(entry.cost)<1 or int(entry.cost)>4:return false
 return true
static func _groups(catalog:Array)->Dictionary:
 var result:Dictionary={}
 for entry in catalog:
  var cost:int=int(entry.cost)
  if not result.has(cost):result[cost]=[]
  result[cost].append(entry)
 return result
static func describe(catalog:Array,level:int,weighted:bool)->Array:
 var groups:Dictionary=_groups(catalog);var weights:Dictionary={};var total:=0
 var costs:Array=groups.keys();costs.sort()
 for cost in costs:
  var weight:int=int(LEVEL_WEIGHTS[level][cost]) if weighted else groups[cost].size()
  weights[cost]=weight;total+=weight
 var rows:Array=[]
 for cost in costs:rows.append({"cost":cost,"characters":groups[cost].size(),"percent":100.0*weights[cost]/total})
 return rows
static func pick(catalog:Array,level:int,random_index:Callable)->Dictionary:
 var groups:Dictionary=_groups(catalog);var total:=0
 for cost in [1,2,3,4]:
  if groups.has(cost):total+=int(LEVEL_WEIGHTS[level][cost])
 var ticket:int=random_index.call(total)
 for cost in [1,2,3,4]:
  if not groups.has(cost):continue
  var weight:int=int(LEVEL_WEIGHTS[level][cost])
  if ticket<weight:return groups[cost][int(random_index.call(groups[cost].size()))]
  ticket-=weight
 return {}
