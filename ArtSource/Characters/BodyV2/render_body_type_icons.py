"""Render matched transparent body-type silhouettes directly from the game meshes."""
import bpy,os
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))
project=os.path.abspath(os.path.join(root,'../../..'))
out=os.path.join(project,'Content/Slate/Textures');os.makedirs(out,exist_ok=True)
for label,file,name in [('Male','FableForge_BodyV2.blend','basecharacter_v2'),('Female','FableForge_FemaleV2.blend','femalecharacter_v2')]:
 bpy.ops.wm.open_mainfile(filepath=os.path.join(root,file))
 mesh=bpy.data.objects[name];rig=next(m.object for m in mesh.modifiers if m.type=='ARMATURE');rig.animation_data_clear();rig.data.pose_position='REST'
 if mesh.data.shape_keys:
  for key in mesh.data.shape_keys.key_blocks:key.value=0
 for obj in bpy.data.objects:
  obj.hide_render=obj!=mesh and obj.type!='ARMATURE'
 # An emission-only surface makes a true flat silhouette, without highlights or facial details.
 material=bpy.data.materials.new('BodyTypeSilhouette');material.use_nodes=True
 nodes=material.node_tree.nodes;nodes.clear();output=nodes.new('ShaderNodeOutputMaterial');emission=nodes.new('ShaderNodeEmission');emission.inputs['Color'].default_value=(.045,.021,.010,1);emission.inputs['Strength'].default_value=1
 material.node_tree.links.new(emission.outputs[0],output.inputs['Surface'])
 mesh.data.materials.clear();mesh.data.materials.append(material)
 for face in mesh.data.polygons:face.material_index=0
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=8
 scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.color_depth='8'
 scene.render.resolution_x=512;scene.render.resolution_y=768;scene.render.resolution_percentage=100
 scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
 camera_data=bpy.data.cameras.new('BodyTypeCamera');camera=bpy.data.objects.new('BodyTypeCamera',camera_data);scene.collection.objects.link(camera)
 camera.location=(0,-5,.88);camera.rotation_euler=(Vector((0,0,.88))-camera.location).to_track_quat('-Z','Y').to_euler();camera_data.type='ORTHO';camera_data.ortho_scale=1.97;camera.hide_render=False;scene.camera=camera
 scene.render.filepath=os.path.join(out,'BodyType'+label+'.png');bpy.ops.render.render(write_still=True)
 print('BODY_TYPE_ICON',scene.render.filepath)
