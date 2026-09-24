import bpy,os,json
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))+'/'
bpy.ops.wm.open_mainfile(filepath=root+'FableForge_FemaleV2.blend');f=bpy.data.objects['femalecharacter_v2'];s=bpy.context.scene
s.render.engine='BLENDER_WORKBENCH';s.display.shading.light='STUDIO';s.display.shading.color_type='SINGLE';s.display.shading.single_color=(.65,.43,.32);s.display.shading.show_shadows=False;s.display.shading.show_cavity=True
s.camera.data.type='ORTHO';s.camera.data.ortho_scale=.58;s.render.resolution_x=700;s.render.resolution_y=800;s.render.resolution_percentage=100
for value in [0,.7]:
 f.data.shape_keys.key_blocks['BodyFat'].value=value
 for view,pos in [('front',(0,-3,.95)),('side',(3,0,.95))]:
  s.camera.location=pos;s.camera.rotation_euler=(Vector((0,0,.92))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=root+'groin-before-fat'+str(value)+'-'+view+'.jpg';bpy.ops.render.render(write_still=True)
r=[]
for v in f.data.vertices:
 if abs(v.co.x)<5 and 83<v.co.z<102 and v.co.y<0:
  r.append({'id':v.index,'co':list(v.co),'weights':{f.vertex_groups[g.group].name:round(g.weight,4) for g in v.groups}})
open(root+'groin-before-weights.json','w').write(json.dumps(r,indent=2))
