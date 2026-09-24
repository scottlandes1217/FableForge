import bpy,os,json,math
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))+'/'
default={'BodyBuild':.42,'Muscle':.85,'BodyFat':.08,'ShoulderWidth':.50,'WaistWidth':.05,'HipWidth':.20,'TorsoLength':.05,'JawWidth':.70,'JawDepth':.50,'ChinDepth':.35,'NoseWidth':.45,'EarLength':.55,'EarPoint':.85}
upper={'BodyBuild':.70,'Muscle':1.,'BodyFat':.50,'ShoulderWidth':.80,'WaistWidth':.45,'HipWidth':.50,'TorsoLength':.50,'JawWidth':.95,'JawDepth':.85,'ChinDepth':.70,'NoseWidth':.80,'EarLength':.85,'EarPoint':1.}
report={}
for sex,file,name in [('male','FableForge_BodyV2.blend','basecharacter_v2'),('female','FableForge_FemaleV2.blend','femalecharacter_v2')]:
 bpy.ops.wm.open_mainfile(filepath=root+file);f=bpy.data.objects[name];rig=next(m.object for m in f.modifiers if m.type=='ARMATURE');rig.data.pose_position='REST'
 for o in bpy.data.objects:
  if o.type=='MESH':o.hide_render=o!=f
 s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.display.shading.light='STUDIO';s.display.shading.color_type='SINGLE';s.display.shading.single_color=(.4,.55,.3);s.display.shading.show_shadows=False;s.display.shading.show_cavity=True
 s.camera.data.type='ORTHO';s.camera.data.ortho_scale=2.1;s.render.resolution_x=650;s.render.resolution_y=850;s.render.resolution_percentage=100
 f.data.calc_loop_triangles();basis=f.data.shape_keys.key_blocks['Basis']
 for label,values in [('neutral',{}),('default',default),('upper',upper)]:
  for k in list(f.data.shape_keys.key_blocks)[1:]:k.value=values.get(k.name,0)
  bpy.context.view_layer.update();o=f.evaluated_get(bpy.context.evaluated_depsgraph_get());me=o.to_mesh();flips=0
  for t in f.data.loop_triangles:
   p=[basis.data[i].co for i in t.vertices];q=[me.vertices[i].co for i in t.vertices];n=(p[1]-p[0]).cross(p[2]-p[0]);m=(q[1]-q[0]).cross(q[2]-q[0])
   if n.length>1e-8 and n.dot(m)<0:flips+=1
  chest=[v.co for v in me.vertices if 128<v.co.z<138 and abs(v.co.x)<18]
  arm=[];a=Vector((16.,2.5,143.));b=Vector((32.4,1.8,121.2));axis=b-a;direction=axis.normalized()
  for v in f.data.vertices:
   p=Vector((abs(v.co.x),v.co.y,v.co.z));t=(p-a).dot(axis)/axis.length_squared
   if .35<t<.65 and abs(v.co.x)>18 and (p-(a+axis*t)).length<10:
    q=me.vertices[v.index].co;arm.append(Vector((abs(q.x),q.y,q.z)))
  center=sum(arm,Vector())/len(arm) if arm else Vector()
  radius=sum(((p-center)-direction*(p-center).dot(direction)).length for p in arm)/len(arm) if arm else None
  report[sex+'_'+label]={'flipped_triangles':flips,'chest_depth_cm':max(p.y for p in chest)-min(p.y for p in chest),'same_vertices_upperarm_mean_radius_cm':radius}
  o.to_mesh_clear()
  if label=='neutral':continue
  for view,position in [('front',(0,-4,1.1)),('side',(4,0,1.1))]:
   s.camera.location=position;s.camera.rotation_euler=(Vector((0,0,1))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=root+'orc-'+sex+'-'+label+'-'+view+'.jpg';bpy.ops.render.render(write_still=True)
open(root+'orc-proportion-validation.json','w').write(json.dumps(report,indent=2));print(report)
