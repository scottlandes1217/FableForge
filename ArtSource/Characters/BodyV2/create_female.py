import bpy,bmesh,os,sys,json
import numpy as np
from mathutils import Vector,Matrix,Quaternion
root=os.path.dirname(os.path.abspath(__file__));sys.path.insert(0,root)
from morph_contract import MORPH_NAMES,POSITIVE_ONLY,offset
bpy.ops.wm.open_mainfile(filepath=root+'/FableForge_BodyV2.blend')
base=bpy.data.objects['basecharacter_v2'];rig=next(m.object for m in base.modifiers if m.type=='ARMATURE');rig.animation_data_clear();rig.data.pose_position='REST'
pre=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=root+'/SourcePack/Superhero_Female_FullBody.gltf')
objects=[o for o in bpy.data.objects if o not in pre];source=next(o for o in objects if o.type=='ARMATURE');meshes=[o for o in objects if o.type=='MESH']
mapnames={'root':'pelvis','Head':'head','spine_01':'spine_02','spine_02':'spine_04','spine_03':'spine_05'}
def targetname(n):return mapnames.get(n,n.replace('_04_leaf','_03').replace('ball_leaf','ball'))
transforms={}
for b in source.data.bones:
 name=targetname(b.name)
 if name not in rig.data.bones:continue
 t=rig.data.bones[name];h=source.matrix_world@b.head_local*100;tail=source.matrix_world@b.tail_local*100
 # Match bone-axis direction, retaining authored cross-section rather than copying bone roll.
 next_names={'upperarm':'lowerarm','lowerarm':'hand','thigh':'calf','calf':'foot','foot':'ball','clavicle':'upperarm'}
 next_source=None
 for prefix,nxt in next_names.items():
  if b.name.startswith(prefix+'_'):next_source=nxt+'_'+b.name[-1]
 if next_source and next_source in source.data.bones and targetname(next_source) in rig.data.bones:
  sd=source.matrix_world@source.data.bones[next_source].head_local*100-h
  td=rig.data.bones[targetname(next_source)].head_local-t.head_local
  q=sd.normalized().rotation_difference(td.normalized())
 elif any(k in b.name for k in ['hand','index','middle','ring','pinky','thumb']):
  side=b.name[-1];sb=source.data.bones['hand_'+side];sc=source.data.bones['middle_01_'+side];tb=rig.data.bones['hand_'+side];tc=rig.data.bones['middle_01_'+side]
  q=(sc.head_local-sb.head_local).normalized().rotation_difference((tc.head_local-tb.head_local).normalized())
 else:q=Quaternion()
 target_head=t.head_local.copy()
 if b.name=='pelvis' or b.name.startswith('spine_'):target_head=h+Vector((0,-4,2))
 if b.name=='Head':target_head=h+Vector((0,-1,0))
 transforms[b.name]=(name,h,target_head,q)
for o in meshes:
 # UV seam duplicates must share weights before rebind, preventing visible midline cracks.
 seam={}
 for v in o.data.vertices:seam.setdefault(tuple(round(c,5) for c in v.co),[]).append(v.index)
 for ids in seam.values():
  if len(ids)<2:continue
  averaged={}
  for i in ids:
   for g in o.data.vertices[i].groups:averaged[g.group]=averaged.get(g.group,0)+g.weight/len(ids)
  for group in o.vertex_groups:group.remove(ids)
  for group,w in averaged.items():o.vertex_groups[group].add(ids,w,'REPLACE')
 positions=[];weights=[]
 for v in o.data.vertices:
  p=o.matrix_world@v.co*100;total=0.;out=Vector();ws={}
  for g in v.groups:
   n=o.vertex_groups[g.group].name
   if n not in transforms:continue
   name,h,th,q=transforms[n];out+=(th+q@(p-h))*g.weight;total+=g.weight;ws[name]=ws.get(name,0)+g.weight
  positions.append(out/total if total else p);weights.append(ws)
 for m in list(o.modifiers):o.modifiers.remove(m)
 o.parent=None;o.matrix_world=base.matrix_world.copy()
 for v,p in zip(o.data.vertices,positions):v.co=p
 o.vertex_groups.clear()
 for n in rig.data.bones.keys():o.vertex_groups.new(name=n)
 for i,ws in enumerate(weights):
  total=sum(ws.values())
  for n,w in ws.items():o.vertex_groups[n].add([i],w/total,'REPLACE')
 o.data.materials.clear();o.data.materials.append(bpy.data.materials.new('Female_'+('skin' if 'Superhero' in o.name else 'eyes' if 'Eyes' in o.name else 'hair')))
# Deterministic sectionorder hair,eyes,skin.
meshes.sort(key=lambda o:2 if 'Superhero' in o.name else 1 if 'Eyes' in o.name else 0)
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:o.select_set(True)
bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();female=bpy.context.object;female.name='femalecharacter_v2'
# Remove two near-collinear authored elbow vertices; these sliver triangles reverse
# under otherwise smooth morph deformation. Retriangulate the local n-gons.
bm=bmesh.new();bm.from_mesh(female.data)
skinverts=set(v for face in bm.faces if face.material_index==2 for v in face.verts if abs(v.co.x)<7 and 135<v.co.z<155)
bmesh.ops.remove_doubles(bm,verts=list(skinverts),dist=.0001)
# Join only coincident groin UV seam vertices; loop UVs remain separate.
groinverts=[v for v in bm.verts if abs(v.co.x)<7 and 80<v.co.z<113]
bmesh.ops.remove_doubles(bm,verts=groinverts,dist=.0001)
slivers=[v for v in bm.verts if abs(abs(v.co.x)-32.333)<.01 and abs(v.co.z-117.988)<.01]
if slivers:bmesh.ops.dissolve_verts(bm,verts=slivers,use_face_split=False,use_boundary_tear=False)
bmesh.ops.triangulate(bm,faces=[face for face in bm.faces if len(face.verts)>3])
bm.to_mesh(female.data);bm.free()
mod=female.modifiers.new('SharedSkeleton','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=False
# Smooth the narrow sternum transition introduced by differing source spine bind positions.
neighbors=[set() for v in female.data.vertices]
for edge in female.data.edges:
 a,b=edge.vertices;neighbors[a].add(b);neighbors[b].add(a)
for iteration in range(8):
 coords=[v.co.copy() for v in female.data.vertices]
 for v in female.data.vertices:
  x,y,z=coords[v.index]
  if abs(x)<3 and 136<z<155 and y<0 and neighbors[v.index]:
   strength=.55*(1-abs(x)/3)*min(1,(z-136)/3,(155-z)/3)
   avg=sum((coords[j] for j in neighbors[v.index]),Vector())/len(neighbors[v.index])
   v.co=coords[v.index].lerp(avg,strength)
# The authored front underwear has a recessed center seam even at rest.
# Bring this narrow strip onto the surrounding fabric surface without changing
# the leg opening, posterior, or outer silhouette. Coordinates are centimetres.
def groin_bell(value,center,radius):
 t=max(0.,1-abs(value-center)/radius)
 return t*t*(3-2*t)
for v in female.data.vertices:
 x,y,z=v.co
 t=max(0.,min(1.,-y/4.));front=t*t*(3-2*t)
 v.co.y-=1.8*groin_bell(x,0,1.4)*groin_bell(z,91,9)*front
# Fit the remaining center ridge/recess to adjacent front cross-sections.
coords=[v.co.copy() for v in female.data.vertices]
for v in female.data.vertices:
 x,y,z=v.co
 if abs(x)<2 and 88<z<112 and y<-5:
  candidates=[p for p in coords if 2<abs(p.x)<6 and abs(p.z-z)<5 and p.y<-5]
  if len(candidates)<6:continue
  A=np.array([[1,p.z-z,(p.z-z)**2,p.x**2] for p in candidates]);b=np.array([p.y for p in candidates]);w=np.array([1/(1+((p.z-z)/2)**2) for p in candidates]);coef=np.linalg.lstsq(A*w[:,None],b*w,rcond=None)[0];target=coef[0]+coef[3]*x*x
  fade=max(0,1-abs(x)/2);fade=fade*fade*(3-2*fade);zf=min(1,(z-88)/2,(112-z)/3);zf=zf*zf*(3-2*zf)
  v.co.y+=(target-y)*fade*zf
female.shape_key_add(name='Basis')
for name in MORPH_NAMES:
 k=female.shape_key_add(name=name,from_mix=False);k.value=0;k.slider_min=0 if name in POSITIVE_ONLY else -1;k.slider_max=1
 for v,p in zip(female.data.vertices,k.data):
  # Authored female is already the female endpoint; channel remains a mild silhouette dial.
  d=Vector(offset(name,v.co))*(.10 if name=='FemaleBody' else 1. if name=='HeadSize' else .8)
  p.co=v.co+d
for poly in female.data.polygons:poly.use_smooth=True
female.data.normals_split_custom_set([(0.,0.,0.)]*len(female.data.loops))
for o in bpy.data.objects:
 if o.type=='MESH':o.hide_render=o!=female
bpy.ops.wm.save_as_mainfile(filepath=root+'/FableForge_FemaleV2.blend')
bpy.ops.object.select_all(action='DESELECT');female.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=female
for i,name in enumerate(['MI_Hair_1_002','MI_Eyes_003','skin']):
 previous=bpy.data.materials.get(name)
 if previous:previous.name=name+'_Authoring'
 female.data.materials[i]=bpy.data.materials.new(name)
bpy.ops.export_scene.fbx(filepath=root+'/femalecharacter_v2.fbx',use_selection=True,object_types={'MESH','ARMATURE'},add_leaf_bones=False,bake_anim=False,use_armature_deform_only=False,use_mesh_modifiers=False,mesh_smooth_type='FACE')
print('FEMALE_EXPORTED',len(female.data.vertices))
