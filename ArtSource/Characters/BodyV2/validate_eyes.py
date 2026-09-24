import bpy,json,os
from mathutils import Vector
root=os.path.dirname(os.path.abspath(__file__))+'/'
bpy.ops.wm.open_mainfile(filepath=root+'FableForge_FemaleV2.blend');f=bpy.data.objects['femalecharacter_v2'];s=bpy.context.scene
s.render.engine='BLENDER_WORKBENCH';s.display.shading.light='STUDIO';s.display.shading.color_type='SINGLE';s.display.shading.single_color=(.6,.45,.35);s.display.shading.show_shadows=False;s.display.shading.show_cavity=True
s.camera.location=(0,-3,1.66);s.camera.rotation_euler=(Vector((0,0,1.64))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.type='ORTHO';s.camera.data.ortho_scale=.26;s.render.resolution_x=700;s.render.resolution_y=700;s.render.resolution_percentage=100
ids=set(v for p in f.data.polygons if p.material_index==1 for v in p.vertices);report={}
for name in ['EyeSize','EyeSpacing']:
 k=f.data.shape_keys.key_blocks[name];basis=f.data.shape_keys.key_blocks['Basis'];report[name]={'eyeball_vertices_affected':sum((k.data[i].co-basis.data[i].co).length>.0001 for i in ids),'eyeball_vertices':len(ids)}
 for value in [-1,1]:
  k.value=value;s.render.filepath=root+name+'-'+str(value)+'.jpg';bpy.ops.render.render(write_still=True)
 k.value=0
facial=['JawWidth','CheekWidth','NoseWidth','EarLength','ChinHeight','ChinDepth','JawDepth','CheekFullness','NoseLength','NoseHeight','EyeSize','EyeSpacing','BrowHeight','MouthWidth','LipFullness','EarPoint']
report['head_only']=all((f.data.shape_keys.key_blocks[n].data[v.index].co-v.co).length<.00001 for n in facial for v in f.data.vertices if v.co.z<=152)
assert report['head_only'];open(root+'eyes-validation.json','w').write(json.dumps(report,indent=2));print(report)
