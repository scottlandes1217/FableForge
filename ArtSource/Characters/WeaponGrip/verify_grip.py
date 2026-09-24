"""Render reference-space hand closure against the exported in-game sword."""
import bpy,math,os,sys
from mathutils import Vector,Quaternion,Matrix
ROOT='/Users/scottlandes/Projects/FableForge'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=ROOT+'/ArtSource/Characters/WeaponGrip/sword.fbx')
source=next(o for o in bpy.data.objects if o.type=='MESH')
sword_vertices=[list(source.matrix_world@v.co*100) for v in source.data.vertices]
sword_faces=[list(p.vertices) for p in source.data.polygons]
female='--female' in sys.argv
bpy.ops.wm.open_mainfile(filepath=ROOT+'/ArtSource/Characters/BodyV2/'+('FableForge_FemaleV2.blend' if female else 'FableForge_BodyV2.blend'))
body=bpy.data.objects['femalecharacter_v2' if female else 'basecharacter_v2'];rig=next(m.object for m in body.modifiers if m.type=='ARMATURE')
rig.animation_data_clear();rig.data.pose_position="POSE"
rig.parent=None;body.parent=None
rig.matrix_world=Matrix.Identity(4);body.matrix_world=Matrix.Identity(4)
for o in list(bpy.data.objects):
 if o not in [body,rig]:bpy.data.objects.remove(o,do_unlink=True)
pose={b.name:b.matrix_local.copy() for b in rig.data.bones}
hand='hand_r'
def rotate(name,q):
 pivot=pose[name].translation.copy();m=Matrix.Translation(pivot)@q.to_matrix().to_4x4()@Matrix.Translation(-pivot)
 for b in rig.data.bones:
  if b.name==name or name in [p.name for p in b.parent_recursive]:pose[b.name]=m@pose[b.name]
axis=pose[hand].to_quaternion()@Vector((0,0,1))
for f in ['index','middle','ring','pinky']:
 for j,a in enumerate([-105,-90,-65],1):rotate(f'{f}_{j:02}_r',Quaternion(axis,math.radians(a)))
tip='thumb_03_r';off=rig.data.bones[tip].matrix_local.to_quaternion().inverted()@((rig.data.bones[tip].head_local-rig.data.bones['thumb_02_r'].head_local).normalized()*2)
target=pose[hand]@Vector((-7.012134+.5,2.048732+1.6,.3))
for _ in range(4):
 for j in [3,2,1]:
  n=f'thumb_{j:02}_r';pivot=pose[n].translation;end=pose[tip]@off
  q=(end-pivot).normalized().rotation_difference((target-pivot).normalized())
  if q.angle>math.radians(35):q=Quaternion().slerp(q,math.radians(35)/q.angle)
  rotate(n,q)
for b in rig.pose.bones:
 b.matrix=pose[b.name];bpy.context.view_layer.update()
bpy.context.view_layer.update()
# Exported FBX is metres. Bake its source world transform before attachment.
mesh=bpy.data.meshes.new('SwordGeometry');mesh.from_pydata(sword_vertices,[],sword_faces);mesh.update()
sword=bpy.data.objects.new('Sword',mesh);bpy.context.collection.objects.link(sword)
socket=Matrix.Translation(Vector((-7.012134,2.048732,0)))@Matrix.Rotation(math.pi/2,4,'Z')
sword.matrix_world=rig.matrix_world@pose[hand]@socket@Matrix.Translation(Vector((0,0,-1)))
for o in list(bpy.data.objects):
 if o not in [body,rig,sword]:bpy.data.objects.remove(o,do_unlink=True)
# Neutral material rendering makes grip penetration visible.
body.data.materials.clear();m=bpy.data.materials.new('Skin verification');m.diffuse_color=(.55,.31,.20,1);body.data.materials.append(m)
for p in body.data.polygons:p.material_index=0
sword.data.materials.clear();m=bpy.data.materials.new('Sword verification');m.diffuse_color=(.18,.22,.29,1);sword.data.materials.append(m)
for p in sword.data.polygons:p.material_index=0
center=rig.matrix_world@(pose[hand]@Vector((-7,2,0)))
scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1100;scene.render.resolution_y=850;scene.render.resolution_percentage=100
scene.world.color=(.12,.12,.12);scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True;scene.display.shading.cavity_type='BOTH'
bpy.ops.object.camera_add();cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=30
for name,off in [('palm',Vector((-.18,-.28,.15))),('back',Vector((.2,.25,.15)))]:
 cam.location=center+off*100;cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=ROOT+'/ArtSource/Characters/WeaponGrip/grip_'+('female_' if female else '')+name+'.png';bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/ArtSource/Characters/WeaponGrip/'+('FemaleGripValidation.blend' if female else 'GripValidation.blend'))
