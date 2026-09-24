import bpy,json,math,os
from collections import defaultdict
from mathutils import Vector
out=os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=out+'/../ClothingRepair/FableForge_Character_Clothing_Repair.blend')
s=bpy.context.scene
body=next(o for o in s.objects if o.type=='MESH' and o.name.startswith('body_'))
shirt=next(o for o in s.objects if o.type=='MESH' and o.name.startswith('shirt_'))
shirt.hide_render=True
coords=[body.matrix_world@v.co for v in body.data.vertices]
skin=set(i for p in body.data.polygons if p.material_index==2 for i in p.vertices)
keys={};members=[];mapping={}
for i in skin:
 key=tuple(round(x,5) for x in coords[i])
 if key not in keys:keys[key]=len(members);members.append([])
 group=keys[key];members[group].append(i);mapping[i]=group
neighbors=[set() for m in members]
for e in body.data.edges:
 a,b=e.vertices
 if a in mapping and b in mapping and mapping[a]!=mapping[b]:
  neighbors[mapping[a]].add(mapping[b]);neighbors[mapping[b]].add(mapping[a])
original=[];strength=[]
for ids in members:
 weights=defaultdict(float)
 for i in ids:
  for g in body.data.vertices[i].groups:weights[g.group]+=g.weight/len(ids)
 original.append(dict(weights))
 x,y,z=coords[ids[0]]
 shoulder=min((abs(x)-.10)/.04,(.48-abs(x))/.04,(z-1.05)/.05,(1.57-z)/.05)
 hips=min((z-.72)/.06,(1.13-z)/.06)
 strength.append(max(0,min(1,hips)))
def assign(weights):
 for g in body.vertex_groups:g.remove(list(skin))
 for ids,ws in zip(members,weights):
  total=sum(ws.values())
  for g,w in ws.items():
   if w>0.0001:body.vertex_groups[g].add(ids,w/total,'REPLACE')
 body.data.update()
def measure():
 edges=[tuple(e.vertices) for e in body.data.edges if all(i in mapping for i in e.vertices) and (coords[e.vertices[0]]-coords[e.vertices[1]]).length>.003]
 worst=[0]*len(edges)
 for frame in range(1,56,3):
  s.frame_set(frame);ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh()
  for k,(i,j) in enumerate(edges):
   ratio=(ev.matrix_world.to_3x3()@(me.vertices[i].co-me.vertices[j].co)).length/(coords[i]-coords[j]).length
   worst[k]=max(worst[k],ratio)
  ev.to_mesh_clear()
 result={}
 for name,sel in [('arms',lambda p:p.z>1.13 and abs(p.x)>.1),('hips',lambda p:.72<p.z<1.13)]:
  vals=sorted(w for (i,j),w in zip(edges,worst) if sel(coords[i]) and sel(coords[j]))
  result[name]={'max_edge_stretch':max(vals),'p99':vals[int(len(vals)*.99)],'edges_over_3x':sum(v>3 for v in vals)}
 return result
report={'original':measure()}
saved={}
bpy.ops.wm.open_mainfile(filepath=out+'/FableForge_BodyV2.blend')
v2=bpy.data.objects['basecharacter_v2']
saved={v.index:{v2.vertex_groups[g.group].name:g.weight for g in v.groups} for v in v2.data.vertices}
bpy.ops.wm.open_mainfile(filepath=out+'/../ClothingRepair/FableForge_Character_Clothing_Repair.blend')
s=bpy.context.scene;body=next(o for o in s.objects if o.type=='MESH' and o.name.startswith('body_'))
for g in body.vertex_groups:g.remove(list(saved.keys()))
for i,ws in saved.items():
 for name,w in ws.items():body.vertex_groups[name].add([i],w,'REPLACE')
body.data.update();report['final_v2']=measure();open(out+'/hip-final-validation.json','w').write(json.dumps(report,indent=2));print(report)
