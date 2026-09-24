"""Rebind authored peasant trousers/boots to the playable rig; preserve UVs."""
import bpy,bmesh,os,sys,json
from mathutils import Vector,Quaternion
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform
root=os.path.dirname(os.path.abspath(__file__));sys.path.insert(0,root+'/../BodyV2')
from morph_contract import MORPH_NAMES,POSITIVE_ONLY,offset
source_dir='/Users/scottlandes/Downloads/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Modular Parts/'
report=[]
for female in [False,True]:
 for part in ['legs','feet']:
  bpy.ops.wm.open_mainfile(filepath=root+'/../BodyV2/'+('FableForge_FemaleV2.blend' if female else 'FableForge_BodyV2.blend'))
  body=bpy.data.objects['femalecharacter_v2' if female else 'basecharacter_v2'];rig=next(m.object for m in body.modifiers if m.type=='ARMATURE');rig.animation_data_clear();rig.data.pose_position='REST'
  for k in body.data.shape_keys.key_blocks if body.data.shape_keys else []: k.value=0
  previous=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=source_dir+('Female' if female else 'Male')+'_Peasant_'+part.title()+'.gltf')
  imported=[o for o in bpy.data.objects if o not in previous];source=next(o for o in imported if o.type=='ARMATURE');cloth=next(o for o in imported if o.type=='MESH' and 'Peasant' in o.name)
  names={'root':'pelvis','Head':'head','spine_01':'spine_02','spine_02':'spine_04','spine_03':'spine_05'}
  transforms={}
  for b in source.data.bones:
   name=names.get(b.name,b.name.replace('_04_leaf','_03').replace('ball_leaf','ball'))
   if name not in rig.data.bones:continue
   t=rig.data.bones[name];h=source.matrix_world@b.head_local*100;th=t.head_local.copy();q=Quaternion()
   nxt=next((v+'_'+b.name[-1] for k,v in [('thigh','calf'),('calf','foot'),('foot','ball')] if b.name.startswith(k+'_')),None)
   if nxt and nxt in source.data.bones and nxt in rig.data.bones:
    sd=source.matrix_world@source.data.bones[nxt].head_local*100-h;td=rig.data.bones[nxt].head_local-th;q=sd.normalized().rotation_difference(td.normalized())
   transforms[b.name]=(name,h,th,q)
  if part in ['legs','feet']:
   bm=bmesh.new();bm.from_mesh(cloth.data);bmesh.ops.subdivide_edges(bm,edges=list(bm.edges),cuts=1,use_grid_fill=True);bm.to_mesh(cloth.data);bm.free()
  positions=[];weights=[]
  for v in cloth.data.vertices:
   p=cloth.matrix_world@v.co*100;out=Vector();total=0;ws={}
   for g in v.groups:
    n=cloth.vertex_groups[g.group].name
    if n not in transforms:continue
    name,h,th,q=transforms[n];out+=(th+q@(p-h))*g.weight;total+=g.weight;ws[name]=ws.get(name,0)+g.weight
   positions.append(out/total if total else p);weights.append(ws)
  for m in list(cloth.modifiers):cloth.modifiers.remove(m)
  cloth.parent=None;cloth.matrix_world=body.matrix_world.copy();cloth.vertex_groups.clear()
  for n in rig.data.bones.keys():cloth.vertex_groups.new(name=n)
  # The authored outfit was built for a narrower body. Keep its silhouette, but
  # push buried vertices outside the actual rest surface, including shoe soles.
  skinfaces=[tuple(p.vertices) for p in body.data.polygons if p.material_index==2]
  bvh=BVHTree.FromPolygons([v.co.copy() for v in body.data.vertices],skinfaces)
  corrected=0
  for v,p,ws in zip(cloth.data.vertices,positions,weights):
   hit,normal,face,dist=bvh.find_nearest(p)
   if hit is not None and (p-hit).dot(normal)<(1.5 if part=='feet' else 1.0):
    p=hit+normal*(1.5 if part=='feet' else 1.0);corrected+=1
   if part=='legs' and hit is not None and p.z>99:
    # Keep the waistband outside the body/tunic clearance envelope.  The
    # tunic shell is offset 1.1 cm from the body, so tucking this region to
    # +0.4 cm exposed a jagged strip of skin at the rear waist in gameplay.
    # Blend the upper trousers to a 0.65 cm clearance beneath the tunic while
    # retaining the authored silhouette below the overlap.
    tuck=min(1.,(p.z-99.)/3.);p=p.lerp(hit+normal*.65,tuck)
   if face is not None:
    ws={};factors=[1./max(.01,(body.data.vertices[i].co-hit).length_squared) for i in skinfaces[face]];normalizer=sum(factors)
    for i,factor in zip(skinfaces[face],factors):
     for group in body.data.vertices[i].groups:
      name=body.vertex_groups[group.group].name;ws[name]=ws.get(name,0)+group.weight*factor/normalizer
    ws=dict(sorted(ws.items(),key=lambda pair:pair[1],reverse=True)[:8])
   if part=='feet':
    # Room for the wider playable toes; taper the extra toe-box volume into
    # the ankle so the authored boot shaft and cuff keep their proportions.
    toe=max(0.,min(1.,(17.-p.z)/9.))
    center=14. if p.x>=0 else -14.
    # The original +28%/+22% toe expansion made the boots visibly wider than
    # the playable feet in Unreal. Keep only a small clearance for the wider
    # toe rig while preserving the authored boot silhouette.
    p.x=center+(p.x-center)*(1.+.10*toe)
    p.y=-7.+(p.y+7.)*(1.+.08*toe)
   v.co=p
   total=sum(ws.values())
   for n,w in ws.items():cloth.vertex_groups[n].add([v.index],w/total,'REPLACE')
  mod=cloth.modifiers.new('Shared playable skeleton','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=False
  if part in ['feet','legs']:
   # A closed lining follows the exact body surface/weights. The
   # authored boot shell contains open rear/heel panels; lining fills those
   # openings without changing the recognizable straps and cuff silhouette.
   liner=body.copy();liner.data=body.data.copy();bpy.context.collection.objects.link(liner)
   if liner.data.shape_keys:liner.shape_key_clear()
   bm=bmesh.new();bm.from_mesh(liner.data)
   bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index!=2],context='FACES')
   bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.0001,plane_co=(0,0,44 if part=='feet' else 116),plane_no=(0,0,1),clear_outer=True,clear_inner=False)
   if part=='legs':
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.0001,plane_co=(0,0,94),plane_no=(0,0,-1),clear_outer=True,clear_inner=False)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if abs(f.calc_center_median().x)>27],context='FACES')
   bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.02);bm.normal_update()
   for v in bm.verts:
    # Extra room at heel/Achilles survives ankle flexion and imported linear
    # skinning; the outer authored shell still supplies the visible detail.
    if part=='feet':
     clearance=.9 if v.co.z<18 else .7
    else:
     # Keep the inner waistband under the tunic's 1.1 cm shell clearance while
     # still closing the body gap across the rear pelvis.
     clearance=.6 if v.co.z>100 else .5
    v.co+=v.normal*clearance
   for f in bm.faces:f.material_index=0
   bm.to_mesh(liner.data);bm.free();liner.data.materials.clear()
   if part=='legs':
    # The trouser liner is an overlap fill, so it must use the same cloth
    # material as the shell.  A separate leather slot made the exposed upper
    # liner read as a dark/purple atlas patch at the rear waistband.
    liner.data.materials.append(cloth.data.materials[0])
   else:
    leather=bpy.data.materials.new('Boot_Leather_Lining');leather.diffuse_color=(.055,.026,.012,1);liner.data.materials.append(leather)
   bpy.ops.object.select_all(action='DESELECT');cloth.select_set(True);liner.select_set(True);bpy.context.view_layer.objects.active=cloth;bpy.ops.object.join()
  # Transfer atlas UVs from the authored shell to its matching lining. Using
  # the same material/atlas prevents contrasting jagged overlay boundaries.
  uv=cloth.data.uv_layers[0];triangles=[];triangle_uvs=[]
  for face in cloth.data.polygons:
   if face.material_index!=0:continue
   loops=list(face.loop_indices)
   for k in range(1,len(loops)-1):
    ids=[loops[0],loops[k],loops[k+1]];tri=tuple(cloth.data.loops[i].vertex_index for i in ids)
    if len(set(tri))<3:continue
    triangles.append(tri);triangle_uvs.append([Vector((uv.data[i].uv.x,uv.data[i].uv.y,0)) for i in ids])
  shell=BVHTree.FromPolygons([v.co.copy() for v in cloth.data.vertices],triangles,all_triangles=True)
  for face in cloth.data.polygons:
   if face.material_index==0:continue
   for loop in face.loop_indices:
    point=cloth.data.vertices[cloth.data.loops[loop].vertex_index].co;hit,normal,index,distance=shell.find_nearest(point)
    if index is not None:
     tri=triangles[index];mapped=barycentric_transform(hit,*[cloth.data.vertices[i].co for i in tri],*triangle_uvs[index]);uv.data[loop].uv=(mapped.x,mapped.y)
  cloth.name=('female' if female else 'male')+'_peasant_'+part+'_v2';asset=cloth.name
  cloth.shape_key_add(name='Basis',from_mix=False).value=0
  for name in MORPH_NAMES:
   key=cloth.shape_key_add(name=name,from_mix=False);key.value=0;key.slider_min=0 if name in POSITIVE_ONLY else -1
   for v in key.data:v.co+=Vector(offset(name,v.co))*(.8 if female else 1)
  for o in bpy.data.objects:
   if o.type=='MESH':o.hide_render=o not in [body,cloth]
  bpy.ops.wm.save_as_mainfile(filepath=root+'/'+asset+'.blend')
  bpy.ops.object.select_all(action='DESELECT');cloth.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=cloth;rig.name='root_001'
  bpy.ops.export_scene.fbx(filepath=root+'/'+asset+'.fbx',use_selection=True,object_types={'MESH','ARMATURE'},add_leaf_bones=False,bake_anim=False,use_armature_deform_only=False,use_mesh_modifiers=False,mesh_smooth_type='FACE')
  report.append(dict(asset=asset,vertices=len(cloth.data.vertices),faces=len(cloth.data.polygons),bones=len(rig.data.bones),corrected_vertices=corrected,bounds=[[min(v.co[i] for v in cloth.data.vertices),max(v.co[i] for v in cloth.data.vertices)] for i in range(3)]))
open(root+'/source-validation.json','w').write(json.dumps(report,indent=2));print(report)
