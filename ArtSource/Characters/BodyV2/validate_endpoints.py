import bpy,json,sys,os
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))+'/'
sys.path.insert(0,root)
from morph_contract import POSITIVE_ONLY
bpy.ops.wm.open_mainfile(filepath=root+'FableForge_BodyV2.blend')
b=next(o for o in bpy.data.objects if o.name=='basecharacter_v2');b.data.calc_loop_triangles();basis=b.data.shape_keys.key_blocks['Basis'];report={}
combined=b.shape_key_add(name='CombinedValidation',from_mix=False)
for v in b.data.vertices:
 combined.data[v.index].co=basis.data[v.index].co+sum((k.data[v.index].co-basis.data[v.index].co for k in list(b.data.shape_keys.key_blocks)[1:-1] if k.name!='FemaleBody'),Vector())
for k in list(b.data.shape_keys.key_blocks)[1:]:
 k.slider_min=-1
 item={}
 for w in ([1] if k.name in POSITIVE_ONLY or k.name=='CombinedValidation' else [-1,1]):
  worst=1.;flips=0
  for t in b.data.loop_triangles:
   p=[basis.data[i].co for i in t.vertices];q=[basis.data[i].co+(k.data[i].co-basis.data[i].co)*w for i in t.vertices]
   n=(p[1]-p[0]).cross(p[2]-p[0]);m=(q[1]-q[0]).cross(q[2]-q[0])
   if n.length>1e-8:worst=min(worst,m.length/n.length);flips+=int(n.dot(m)<0)
  item[str(w)]={'min_triangle_area_ratio':worst,'flipped_triangles':flips}
 report[k.name]=item
open(root+'endpoint-validation.json','w').write(json.dumps(report,indent=2));print(report)
