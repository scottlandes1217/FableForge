"""Render actual item meshes with film transparency; never color-key model pixels."""
import bpy, os, math, numpy as np
from mathutils import Vector
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../..'))
OUT=os.path.join(ROOT,'Content/Slate/ItemIcons')
items=[(n,'ArtSource/ItemProps/'+n+'.blend','SM_'+n,None) for n in ['health_potion','mana_potion','wood','stone','iron_ore','berries','honey','meat']]
items += [('iron_sword','ArtSource/Characters/WeaponGrip/GripValidation.blend','Sword',None),('peasant_chest','ArtSource/Characters/FittedTunic/FittedTunic.blend','peasant_tunic_v2',(.035,.065,.075,.92)),('peasant_legs','ArtSource/Characters/FittedLowerArmor/male_peasant_legs_v2.blend','male_peasant_legs_v2',(.055,.035,.022,.93)),('peasant_feet','ArtSource/Characters/FittedLowerArmor/male_peasant_feet_v2.blend','male_peasant_feet_v2',(.035,.020,.012,.78))]
for name,source,objname,color in items:
 if os.environ.get("ICON_ONLY") and name!=os.environ["ICON_ONLY"]:continue
 bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,source))
 obj=bpy.data.objects[objname]
 for o in bpy.data.objects:
  if o.type=='ARMATURE':o.animation_data_clear();o.data.pose_position='REST'
 bpy.context.view_layer.update()
 deps=bpy.context.evaluated_depsgraph_get()
 mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
 mat=obj.matrix_world.copy()
 for v in mesh.vertices:v.co=mat@v.co
 if name=='iron_sword':
  points=np.array([tuple(v.co) for v in mesh.vertices]);mean=points.mean(axis=0)
  values,vectors=np.linalg.eigh(np.cov((points-mean).T));axis=Vector(vectors[:,-1])
  if axis.z<0:axis=-axis
  rot=axis.rotation_difference(Vector((0,0,1)))
  for v in mesh.vertices:v.co=rot@(v.co-Vector(mean))
 lo=Vector([min(v.co[i] for v in mesh.vertices) for i in range(3)])
 hi=Vector([max(v.co[i] for v in mesh.vertices) for i in range(3)])
 center=(lo+hi)/2;scale=2/max(hi-lo)
 for v in mesh.vertices:v.co=(v.co-center)*scale
 for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
 item=bpy.data.objects.new('IconModel',mesh);bpy.context.collection.objects.link(item)
 if name=='iron_sword':color=(.3,.35,.4,.28)
 if color:
  m=bpy.data.materials.new('MatchingGameSurface');m.use_nodes=True
  bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color[:3],1);bs.inputs['Roughness'].default_value=color[3]
  mesh.materials.clear();mesh.materials.append(m)
  for p in mesh.polygons:p.material_index=0
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
 scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
 scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
 scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.35,.35,.35,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
 scene.view_settings.view_transform='AgX'
 bpy.ops.object.camera_add(location=(2,-7,2));camera=bpy.context.object;camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=2.35;scene.camera=camera
 if name=='iron_sword':item.rotation_euler[1]=math.radians(30)
 for pos,power,size in [((-3,-4,5),650,4),((4,-2,2),450,3),((0,4,3),800,3)]:
  bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
 scene.render.filepath=os.path.join(OUT,name+'.png');bpy.ops.render.render(write_still=True)
 print('TRUE_ALPHA_ICON',name,flush=True)
