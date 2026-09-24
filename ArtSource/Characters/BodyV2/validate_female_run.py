import bpy,os,json
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))+'/'
bpy.ops.wm.open_mainfile(filepath=root+'../ClothingRepair/FableForge_Character_Clothing_Repair.blend')
base=next(o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('body_'));rig=next(m.object for m in base.modifiers if m.type=='ARMATURE')
with bpy.data.libraries.load(root+'FableForge_FemaleV2.blend',link=False) as (a,b):b.objects=['femalecharacter_v2']
f=b.objects[0];bpy.context.collection.objects.link(f)
for m in f.modifiers:
 if m.type=='ARMATURE':m.object=rig
for o in bpy.data.objects:
 if o.type=='MESH':o.hide_render=o!=f
s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.display.shading.light='STUDIO';s.display.shading.color_type='SINGLE';s.display.shading.single_color=(.65,.4,.3)
s.camera.location=(.8,-4,1.2);s.camera.rotation_euler=(Vector((0,0,1))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.type='ORTHO';s.camera.data.ortho_scale=2.1;s.render.resolution_x=700;s.render.resolution_y=900;s.render.resolution_percentage=100
for frame in [6,16,40]:
 s.frame_set(frame);s.render.filepath=root+'female-run-'+str(frame)+'.jpg';bpy.ops.render.render(write_still=True)
print('FEMALE_RUN_RENDERED')
