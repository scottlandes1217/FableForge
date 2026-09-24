import bpy,json,numpy as np,sys
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.kdtree import KDTree
from mathutils.bvhtree import BVHTree
out=Path(__file__).resolve().parent;source=Path('/Users/scottlandes/Downloads/Universal Base Characters[Standard]/Hairstyles/Origin at 0/FBX (Unreal Engine)')
female_target='--female' in sys.argv
bpy.ops.wm.open_mainfile(filepath=str(out.parent/('BodyV2/FableForge_FemaleV2.blend' if female_target else 'BodyV2/FableForge_BodyV2.blend')))
body=bpy.data.objects['femalecharacter_v2' if female_target else 'basecharacter_v2'];ids={i for p in body.data.polygons if p.material_index==0 for i in p.vertices};target=np.array([body.matrix_world@body.data.vertices[i].co for i in sorted(ids)])
skin_vertices=[body.matrix_world@v.co for v in body.data.vertices]
skin_faces=[list(p.vertices) for p in body.data.polygons if p.material_index==2]
scalp=BVHTree.FromPolygons(skin_vertices,skin_faces)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.ops.import_scene.fbx(filepath=str(source/('Eyebrows_Female.fbx' if female_target else 'Eyebrows_Regular.fbx')));o=next(o for o in bpy.context.scene.objects if o.type=='MESH');points=np.array([o.matrix_world@v.co for v in o.data.vertices]);R=np.eye(3);T=target.mean(0)-points.mean(0)
kd=KDTree(len(target))
for i,p in enumerate(target):kd.insert(Vector(p),i)
kd.balance()
for _ in range(60):
 moved=points@R.T+T;matched=np.array([target[kd.find(Vector(p))[1]] for p in moved]);x=moved-moved.mean(0);y=matched-matched.mean(0);u,s,vt=np.linalg.svd(x.T@y);r=vt.T@u.T
 if np.linalg.det(r)<0:vt[-1]*=-1;r=vt.T@u.T
 t=matched.mean(0)-r@moved.mean(0);R=r@R;T=r@T+t
residual=float(np.mean([kd.find(Vector(p))[2] for p in points@R.T+T]));report={'male_source_to_current_rotation':R.tolist(),'translation_m':T.tolist(),'brow_mean_residual_m':residual,'styles':{}}
if '--short-only' in sys.argv:
 old=out/('alignment-female.json' if female_target else 'alignment.json')
 if old.exists():report['styles']=json.loads(old.read_text())['styles']
for f in source.glob('*.fbx'):
 if '--short-only' in sys.argv and f.stem not in ['Hair_Buzzed','Hair_BuzzedFemale']:continue
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.ops.import_scene.fbx(filepath=str(f));objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
 # Female-source styles use female eye/crown height; lift to the male scalp before common pose alignment.
 female=f.stem in ['Hair_Buns','Hair_Long','Hair_BuzzedFemale','Eyebrows_Female'];dz=(0 if female else -.0435) if female_target else (.0435 if female else 0)
 name=('Female_' if female_target else '')+f.stem
 for o in objs:
  mat=o.matrix_world.copy()
  for v in o.data.vertices:
   p=np.array(mat@v.co);p[2]+=dz;v.co=Vector(R@p+T)
  o.matrix_world=Matrix.Identity(4)
 bpy.ops.object.select_all(action='DESELECT')
 for o in objs:o.select_set(True)
 bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();o=bpy.context.object;o.name='SM_'+name
 clearance=None
 if f.stem in ['Hair_Buzzed','Hair_BuzzedFemale']:
  # Close-cropped caps must clear the actual target scalp, not just match brows.
  # Subdivision prevents triangles spanning across the curved skull surface.
  sub=o.modifiers.new('Scalp fitting topology','SUBSURF');sub.subdivision_type='SIMPLE';sub.levels=1
  bpy.ops.object.modifier_apply(modifier=sub.name)
  moved=0;largest=0.;margin=.003
  original=[v.co.copy() for v in o.data.vertices]
  for iteration in range(20):
   for v in o.data.vertices:
    hit,normal,index,distance=scalp.find_nearest(v.co)
    if hit is not None and (v.co-hit).dot(normal)<margin:
     v.co=hit+normal*margin
   lifts={}
   for poly in o.data.polygons:
    midpoint=sum((o.data.vertices[i].co for i in poly.vertices),Vector())/len(poly.vertices)
    hit,normal,index,distance=scalp.find_nearest(midpoint)
    if hit is not None and (midpoint-hit).dot(normal)<.0015:
     delta=normal*(.002-(midpoint-hit).dot(normal))
     for i in poly.vertices:
      if i not in lifts or delta.length>lifts[i].length:lifts[i]=delta
   for i,delta in lifts.items():o.data.vertices[i].co+=delta
  def signed_gap(p):
   hit,normal,index,distance=scalp.find_nearest(p);return (p-hit).dot(normal)
  minimum=min(signed_gap(v.co) for v in o.data.vertices)
  minimum_face=min(signed_gap(sum((o.data.vertices[i].co for i in p.vertices),Vector())/len(p.vertices)) for p in o.data.polygons)
  largest=max((v.co-original[i]).length for i,v in enumerate(o.data.vertices));moved=sum((v.co-original[i]).length>.0001 for i,v in enumerate(o.data.vertices))
  clearance={'moved_vertices':moved,'maximum_displacement_m':largest,'minimum_vertex_clearance_m':minimum,'minimum_face_clearance_m':minimum_face,'target_clearance_m':margin}

 for p in o.data.polygons:p.use_smooth=True
 bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');bpy.ops.wm.save_as_mainfile(filepath=str(out/(name+'.blend')))
 bpy.ops.export_scene.fbx(filepath=str(out/(name+'.fbx')),use_selection=True,object_types={'MESH'},apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
 report['styles'][name]={'female_source':female,'texture':2 if f.stem in ['Hair_Buns','Hair_Long','Eyebrows_Female'] else 1,'vertices':len(o.data.vertices),'scalp_fit':clearance}
target=out/('alignment-female.json' if female_target else 'alignment.json');target.write_text(json.dumps(report,indent=2))
