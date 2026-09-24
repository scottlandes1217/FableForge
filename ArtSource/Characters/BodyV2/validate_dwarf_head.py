import bpy,os,json
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))+'/'
report={}
for sex,file,name,height in [('male','FableForge_BodyV2.blend','basecharacter_v2',.79),('female','FableForge_FemaleV2.blend','femalecharacter_v2',.75)]:
 bpy.ops.wm.open_mainfile(filepath=root+file);f=bpy.data.objects[name];rig=next(m.object for m in f.modifiers if m.type=='ARMATURE');rig.data.pose_position='REST'
 for o in bpy.data.objects:
  if o.type=='MESH':o.hide_render=o!=f
 for key,value in {'BodyBuild':.55,'ShoulderWidth':.55,'WaistWidth':.30,'HipWidth':.25,'BodyFat':.25,'Muscle':.55,'TorsoLength':-.35,'JawWidth':.40,'ChinDepth':.30}.items():f.data.shape_keys.key_blocks[key].value=value
 s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.display.shading.light='STUDIO';s.display.shading.color_type='SINGLE';s.display.shading.single_color=(.6,.43,.3);s.display.shading.show_shadows=False;s.display.shading.show_cavity=True
 s.camera.data.type='ORTHO';s.camera.data.ortho_scale=2.1;s.render.resolution_x=650;s.render.resolution_y=850;s.render.resolution_percentage=100
 f.data.calc_loop_triangles();basis=f.data.shape_keys.key_blocks['Basis']
 for label,value in [('before',0),('default',.67),('maximum',1)]:
  f.data.shape_keys.key_blocks['HeadSize'].value=value;bpy.context.view_layer.update();o=f.evaluated_get(bpy.context.evaluated_depsgraph_get());me=o.to_mesh();flips=0
  for t in f.data.loop_triangles:
   p=[basis.data[i].co for i in t.vertices];q=[me.vertices[i].co for i in t.vertices];n=(p[1]-p[0]).cross(p[2]-p[0]);m=(q[1]-q[0]).cross(q[2]-q[0])
   if n.length>1e-8 and n.dot(m)<0:flips+=1
  head=[me.vertices[v.index].co for v in f.data.vertices if v.co.z>157]
  report[sex+'_'+label]={'flipped_triangles':flips,'head_width_cm':max(p.x for p in head)-min(p.x for p in head),'head_top_cm':max(p.z for p in head),'race_height_scale':height}
  o.to_mesh_clear()
  for view,position in [('front',(0,-4,1.1)),('side',(4,0,1.1))]:
   s.camera.location=position;s.camera.rotation_euler=(Vector((0,0,1))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=root+'dwarf-'+sex+'-'+label+'-'+view+'.jpg';bpy.ops.render.render(write_still=True)
open(root+'dwarf-head-validation.json','w').write(json.dumps(report,indent=2));print(report)
