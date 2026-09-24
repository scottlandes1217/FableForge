import bpy,os,math
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))
for gender in ['male','female']:
 bpy.ops.wm.open_mainfile(filepath=root+'/'+gender+'_peasant_legs_v2.blend')
 body=bpy.data.objects['femalecharacter_v2' if gender=='female' else 'basecharacter_v2'];rig=next(m.object for m in body.modifiers if m.type=='ARMATURE')
 with bpy.data.libraries.load(root+'/'+gender+'_peasant_feet_v2.blend',link=False) as (src,dst):dst.objects=[gender+'_peasant_feet_v2']
 feet=dst.objects[0];bpy.context.collection.objects.link(feet)
 for m in feet.modifiers:
  if m.type=='ARMATURE':m.object=rig
 for o in bpy.data.objects:
  if o.type=='MESH':o.hide_render=o not in [body,feet,bpy.data.objects[gender+'_peasant_legs_v2']]
 scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.color_type='MATERIAL';scene.cycles.samples=12;scene.render.resolution_x=640;scene.render.resolution_y=800;scene.render.resolution_percentage=100
 scene.world.color=(.25,.25,.25)
 for mat in body.data.materials:mat.diffuse_color=(.65,.4,.25,1)
 for o in [feet,bpy.data.objects[gender+'_peasant_legs_v2']]:
  m=bpy.data.materials.new('LeatherPreview');m.diffuse_color=(.19,.10,.055,1);o.data.materials.clear();o.data.materials.append(m)
 bpy.ops.object.camera_add(location=(2.4,-4.8,1.5));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,.65))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=1.55;scene.camera=cam
 bpy.ops.object.light_add(type='AREA',location=(-2,-3,4));bpy.context.object.data.energy=450;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=4
 scene.render.filepath=root+'/'+gender+'-rest-fit.png';bpy.ops.render.render(write_still=True)
