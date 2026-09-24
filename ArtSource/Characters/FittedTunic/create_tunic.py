import bpy,bmesh,os,json,sys
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))
female='--female' in sys.argv
asset='female_tunic_v2' if female else 'peasant_tunic_v2'
bpy.ops.wm.open_mainfile(filepath=os.path.join(root,'../BodyV2/FableForge_FemaleV2.blend' if female else '../ClothingRepair/FableForge_Character_Clothing_Repair.blend'))
body=next(o for o in bpy.data.objects if o.type=='MESH' and (o.name=='femalecharacter_v2' if female else o.name.startswith('body_')))
# Match the corrected male body's shoulder skinning before extracting sleeves.
if not female:
 sys.path.insert(0,os.path.abspath(os.path.join(root,'../BodyV2')))
 from shoulder_weights import stabilize_male_shoulders
 stabilize_male_shoulders(body)
shirt=body.copy();shirt.data=body.data.copy();bpy.context.collection.objects.link(shirt);shirt.name=asset
shirt.shape_key_clear() if shirt.data.shape_keys else None
rig=next(m.object for m in shirt.modifiers if m.type=='ARMATURE')
rig.data.pose_position='REST'
bm=bmesh.new();bm.from_mesh(shirt.data)
bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index!=2],context='FACES')
# Straight tailored hem, open neckline, and short sleeve cuffs; coordinates in the original centimetre mesh.
for point,normal in [((0,0,102),(0,0,-1)),((0,0,151.5),(0,0,1)),((32,0,0),(1,0,0)),((-32,0,0),(-1,0,0))]:
 bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.0001,plane_co=point,plane_no=normal,clear_outer=True,clear_inner=False)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.02)
bm.normal_update()
for v in bm.verts:v.co+=v.normal*1.1
# Subtle woven trim at every finished opening.
for f in bm.faces:f.material_index=1 if any(e.is_boundary for e in f.edges) else 0
bm.to_mesh(shirt.data);bm.free()
face_materials=[p.material_index for p in shirt.data.polygons]
shirt.data.materials.clear()
for name,color in [('Linen_Ochre',(.035,.065,.075,1)),('Woven_Trim',(.07,.032,.012,1))]:
 m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True;m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=color;m.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.92;shirt.data.materials.append(m)
for p,mi in zip(shirt.data.polygons,face_materials):p.use_smooth=True;p.material_index=mi
bpy.ops.object.select_all(action='DESELECT');shirt.select_set(True);bpy.context.view_layer.objects.active=shirt
# Tiny real edge thickness, not the old inflated silhouette.
sol=shirt.modifiers.new('Fabric thickness','SOLIDIFY');sol.thickness=.18;sol.offset=-1
bpy.ops.object.modifier_apply(modifier=sol.name)
sys.path.insert(0,os.path.abspath(os.path.join(root,'../BodyV2')))
from morph_contract import MORPH_NAMES,POSITIVE_ONLY,offset
shirt.shape_key_clear() if shirt.data.shape_keys else None
shirt.shape_key_add(name='Basis',from_mix=False)
for name in MORPH_NAMES:
 key=shirt.shape_key_add(name=name,from_mix=False);key.value=0;key.slider_min=0 if name in POSITIVE_ONLY else -1
 for v in key.data:v.co+=Vector(offset(name,v.co))*(.8 if female else 1.)
for o in bpy.data.objects:
 if o.type=='MESH' and o!=body and o!=shirt:o.hide_render=True
shirt.hide_render=False;body.hide_render=False
rig.data.pose_position='POSE';bpy.context.scene.frame_set(6)
bpy.ops.wm.save_as_mainfile(filepath=root+('/FittedFemaleTunic.blend' if female else '/FittedTunic.blend'))
rig.animation_data_clear();rig.data.pose_position='REST'
bpy.ops.object.select_all(action='DESELECT');shirt.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=shirt
rig.name='root_001'
bpy.ops.export_scene.fbx(filepath=root+'/'+asset+'.fbx',use_selection=True,object_types={'MESH','ARMATURE'},add_leaf_bones=False,bake_anim=False,use_armature_deform_only=False,mesh_smooth_type='FACE',use_mesh_modifiers=False)
print('TUNIC_EXPORTED',len(shirt.data.vertices),len(shirt.data.polygons))
