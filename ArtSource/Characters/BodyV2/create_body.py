import bpy,os,sys,json
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__));sys.path.insert(0,root)
from morph_contract import MORPH_NAMES,POSITIVE_ONLY,offset
from shoulder_weights import stabilize_male_shoulders
bpy.ops.wm.open_mainfile(filepath=root+'/../ClothingRepair/FableForge_Character_Clothing_Repair.blend')
body=next(o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('body_'))
rig=next(m.object for m in body.modifiers if m.type=='ARMATURE')
# UE linear blend skinning cannot reproduce Blender preserve-volume deformation.
# Explicitly match game deformation in authoring previews.
for m in body.modifiers:
 if m.type=='ARMATURE':m.use_deform_preserve_volume=False
# Localized groin stabilization, validated across 19 frames of the imported run.
# Keep the central seam more pelvis-driven; smoothly vanish before the upper thigh.
pelvis=body.vertex_groups['pelvis'].index
for v in body.data.vertices:
 x,y,z=v.co
 tx=max(0.,1.-abs(x)/6.);tz=max(0.,1.-abs(z-89.)/6.)
 alpha=.5*tx*tx*(3.-2.*tx)*tz*tz*(3.-2.*tz)
 if alpha<=0:continue
 weights={g.group:g.weight*(1-alpha) for g in v.groups}
 weights[pelvis]=weights.get(pelvis,0)+alpha
 for g in body.vertex_groups:g.remove([v.index])
 weights=dict(sorted(weights.items(),key=lambda pair:pair[1],reverse=True)[:8]);total=sum(weights.values())
 for group,value in weights.items():body.vertex_groups[group].add([v.index],value/total,'REPLACE')
print('SHOULDER_VERTICES_STABILIZED',stabilize_male_shoulders(body))
body.name='basecharacter_v2';rig.animation_data_clear();rig.data.pose_position='REST'
body.shape_key_add(name='Basis')
metrics={}
for name in MORPH_NAMES:
 key=body.shape_key_add(name=name,from_mix=False);key.value=0;key.slider_min=0 if name in POSITIVE_ONLY else -1;key.slider_max=1
 count=0;maximum=0
 for v,p in zip(body.data.vertices,key.data):
  d=Vector(offset(name,v.co));p.co=v.co+d
  if d.length>.0001:count+=1;maximum=max(maximum,d.length)
 metrics[name]={'affected_vertices':count,'maximum_displacement_cm':maximum}
# Preserve UV splits and material topology; source smooth normals retained.
for p in body.data.polygons:p.use_smooth=True
bpy.ops.object.select_all(action='DESELECT');body.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=body
rig.name='root_001'
bpy.ops.wm.save_as_mainfile(filepath=root+'/FableForge_BodyV2.blend')
# Export material slot names without embedded source image graph duplicates.
for i,name in enumerate(['MI_Hair_1_002','MI_Eyes_003','skin']):
 previous=bpy.data.materials.get(name)
 if previous:previous.name=name+'_Authoring'
 body.data.materials[i]=bpy.data.materials.new(name)
bpy.ops.export_scene.fbx(filepath=root+'/basecharacter_v2.fbx',use_selection=True,object_types={'MESH','ARMATURE'},add_leaf_bones=False,bake_anim=False,use_armature_deform_only=False,use_mesh_modifiers=False,mesh_smooth_type='FACE')
open(root+'/morph-validation.json','w').write(json.dumps({'vertices':len(body.data.vertices),'morphs':metrics,'linear_skinning':True},indent=2))
print('BODY_V2_EXPORTED',metrics)
