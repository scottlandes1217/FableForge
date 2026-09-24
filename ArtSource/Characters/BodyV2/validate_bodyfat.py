import bpy,json,os
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))+'/'
bpy.ops.wm.open_mainfile(filepath=root+'FableForge_FemaleV2.blend');f=bpy.data.objects['femalecharacter_v2'];rig=next(m.object for m in f.modifiers if m.type=='ARMATURE');rig.data.pose_position='REST'
s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.display.shading.light='STUDIO';s.display.shading.color_type='SINGLE';s.display.shading.single_color=(.65,.4,.3)
s.camera.location=(0,-4,1.2);s.camera.rotation_euler=(Vector((0,0,1))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.type='ORTHO';s.camera.data.ortho_scale=2.;s.render.resolution_x=600;s.render.resolution_y=900;s.render.resolution_percentage=100
r={}
for value in [0,.7,1]:
 f.data.shape_keys.key_blocks['BodyFat'].value=value;bpy.context.view_layer.update()
 o=f.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=o.to_mesh();waist=[v.co for v in mesh.vertices if 107<v.co.z<117 and abs(v.co.x)<28];r[value]={'waist_width_cm':max(p.x for p in waist)-min(p.x for p in waist),'waist_depth_cm':max(p.y for p in waist)-min(p.y for p in waist)};o.to_mesh_clear()
 s.render.filepath=root+'female-fat-'+str(value)+'.jpg';bpy.ops.render.render(write_still=True)
open(root+'bodyfat-validation.json','w').write(json.dumps(r,indent=2));print(r)
