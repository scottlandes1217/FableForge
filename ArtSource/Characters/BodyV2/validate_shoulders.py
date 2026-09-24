import bpy,sys
from mathutils import Vector
root='/Users/scottlandes/Projects/FableForge/ArtSource/Characters/BodyV2/'
for animation in ['jump','walk','jogright']:
 bpy.ops.wm.open_mainfile(filepath=root+'FableForge_BodyV2.blend');f=bpy.data.objects['basecharacter_v2'];bpy.ops.import_scene.fbx(filepath=root+'ValidationAnimations/'+animation+'.fbx');rig=next(o for o in bpy.context.selected_objects if o.type=='ARMATURE')
 for mod in f.modifiers:
  if mod.type=='ARMATURE':mod.object=rig
 # The saved BodyV2 already contains corrected shoulder weights.
 for o in bpy.data.objects:
  if o.type=='MESH':o.hide_render=o!=f
 s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.display.shading.light='STUDIO';s.display.shading.color_type='SINGLE';s.display.shading.single_color=(.65,.4,.3);s.display.shading.show_shadows=False;s.camera.location=(.5,-4,1.5);s.camera.rotation_euler=(Vector((0,0,1.4))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.type='ORTHO';s.camera.data.ortho_scale=1.1;s.render.resolution_x=650;s.render.resolution_y=750;s.render.resolution_percentage=100
 f.data.shape_keys.key_blocks['Muscle'].value=1
 for frame in [6,16,30]:
  s.frame_set(frame);s.render.filepath=root+'shoulder-validated-'+animation+'-'+str(frame)+'.jpg';bpy.ops.render.render(write_still=True)
