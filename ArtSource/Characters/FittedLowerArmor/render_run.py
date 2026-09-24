import bpy,os,json
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))
for gender in ['male','female']:
 bpy.ops.wm.open_mainfile(filepath=root+'/../ClothingRepair/FableForge_Character_Clothing_Repair.blend')
 original=next(o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('body_'));rig=next(m.object for m in original.modifiers if m.type=='ARMATURE')
 specs=[(root+'/../BodyV2/'+('FableForge_FemaleV2.blend' if gender=='female' else 'FableForge_BodyV2.blend'),'femalecharacter_v2' if gender=='female' else 'basecharacter_v2')]+[(root+'/'+gender+'_peasant_'+p+'_v2.blend',gender+'_peasant_'+p+'_v2') for p in ['legs','feet']]
 specs.append((root+'/../FittedTunic/'+('FittedFemaleTunic.blend' if gender=='female' else 'FittedTunic.blend'),'female_tunic_v2' if gender=='female' else 'peasant_tunic_v2'))
 visible=[]
 for path,name in specs:
  with bpy.data.libraries.load(path,link=False) as (a,b):b.objects=[name]
  o=b.objects[0];bpy.context.collection.objects.link(o);visible.append(o)
  for m in o.modifiers:
   if m.type=='ARMATURE':m.object=rig;m.use_deform_preserve_volume=False
  for k in o.data.shape_keys.key_blocks if o.data.shape_keys else []:k.value=0
  for mat in o.data.materials:mat.diffuse_color=(.65,.4,.25,1) if len(visible)==1 else ((.035,.065,.075,1) if 'tunic' in o.name else (.15,.085,.04,1))
 for o in bpy.data.objects:
  if o.type=='MESH':o.hide_render=o not in visible
 s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.display.shading.color_type='MATERIAL';s.camera.location=(2,-4,1.4);s.camera.rotation_euler=(Vector((0,0,.8))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.type='ORTHO';s.camera.data.ortho_scale=1.7;s.render.resolution_x=640;s.render.resolution_y=800;s.render.resolution_percentage=100
 for frame in [6,16,40]:
  s.frame_set(frame);s.render.filepath=root+'/'+gender+'-run-'+str(frame)+'.jpg';bpy.ops.render.render(write_still=True)

 for o in visible:
  for name,value in {'BodyFat':.6,'BodyBuild':.4,'HipWidth':.3,'Muscle':.4}.items():
   if o.data.shape_keys and name in o.data.shape_keys.key_blocks:o.data.shape_keys.key_blocks[name].value=value
 s.frame_set(16);s.render.filepath=root+'/'+gender+'-broad-run.jpg';bpy.ops.render.render(write_still=True)

 for o in visible:
  for k in o.data.shape_keys.key_blocks if o.data.shape_keys else []:k.value=0
 s.camera.location=(1.4,4,1.4);s.camera.rotation_euler=(Vector((0,0,.7))-s.camera.location).to_track_quat('-Z','Y').to_euler()
 rig.data.pose_position='REST';s.render.filepath=root+'/'+gender+'-rear-rest.jpg';bpy.ops.render.render(write_still=True)
 rig.data.pose_position='POSE'
 for frame in [16,40]:
  s.frame_set(frame);s.render.filepath=root+'/'+gender+'-rear-run-'+str(frame)+'.jpg';bpy.ops.render.render(write_still=True)
