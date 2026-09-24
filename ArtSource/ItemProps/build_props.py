import bpy, math, random
from pathlib import Path
from mathutils import Vector
random.seed(24)
OUT=Path(__file__).resolve().parent
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def mat(n,c,metal=0,rough=.55):
 m=bpy.data.materials.new(n); m.diffuse_color=(*c,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*c,1); p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 return m
wood=mat('Dark oak bark',(.16,.068,.025)); cut=mat('Fresh cut timber',(.52,.30,.12)); iron=mat('Weathered iron',(.17,.19,.20),.75); gold=mat('Aged brass',(.42,.26,.055),.7); cork=mat('Natural cork',(.37,.23,.10)); red=mat('Ruby glazed potion',(.43,.012,.025),.22,.22); blue=mat('Sapphire glazed potion',(.015,.12,.47),.25,.21); rock=mat('Warm slate',(.24,.26,.24)); ore=mat('Iron oxide vein',(.37,.16,.065),.65); meat=mat('Cured venison',(.31,.047,.03)); fat=mat('Ivory bone',(.79,.69,.47)); honey=mat('Honey glazed earthenware',(.60,.27,.028),.18,.27); berry=mat('Dark forest berries',(.13,.016,.075),.05,.3); green=mat('Sage leaf',(.075,.16,.032)); rope=mat('Hemp binding',(.49,.36,.19))
def finish(o,m): o.data.materials.append(m); return o
def uv(n,loc,scale,m):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=loc);o=bpy.context.object;o.name=n;o.scale=scale;finish(o,m)
 for p in o.data.polygons:p.use_smooth=True
 return o
def cyl(n,loc,r,d,m,verts=32):
 bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=d,location=loc);o=bpy.context.object;o.name=n;finish(o,m)
 mod=o.modifiers.new('Soft crafted edges','BEVEL');mod.width=.002;mod.segments=2;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 return o
def tor(n,loc,major,minor,m):
 bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=32,minor_segments=8,location=loc);return finish(bpy.context.object,m)
def stone(n,loc,scale,m):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=loc);o=bpy.context.object;o.name=n
 for v in o.data.vertices:v.co*=random.uniform(.85,1.13)
 o.scale=scale;return finish(o,m)
def save(name):
 bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=bpy.context.selected_objects[0];bpy.ops.object.convert(target='MESH');bpy.ops.object.join();o=bpy.context.object;o.name='SM_'+name
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(name+'.blend')))
 bpy.ops.export_scene.fbx(filepath=str(OUT/(name+'.fbx')),use_selection=True,object_types={'MESH'},apply_unit_scale=True,add_leaf_bones=False,bake_anim=False,mesh_smooth_type='FACE')
 bpy.ops.object.delete(use_global=False)
for name,m in [('health_potion',red),('mana_potion',blue)]:
 uv('Hand blown ceramic flask',(0,0,.084),(.061,.047,.075),m);cyl('Neck',(0,0,.157),.023,.049,m);tor('Brass lip',(0,0,.175),.024,.004,gold);cyl('Stopper',(0,0,.187),.020,.026,cork);tor('Shoulder band',(0,0,.117),.046,.003,gold)
 # Raised identifying brass seal on the front.
 seal=cyl('Apothecary seal',(0,-.047,.09),.018,.004,gold);seal.rotation_euler[0]=math.pi/2
 save(name)
for x,y in [(-.042,0),(.042,0),(0,.069)]:
 o=cyl('Split firewood',(x,y,.17),.042,.34,wood,12)
 cyl('End grain',(x,y,.341),.039,.002,cut,12)
for z in [.08,.26]:
 o=tor('Hemp bundle binding',(0,.02,z),.085,.005,rope);o.scale.y=.85
save('wood')
stone('River stone',(0,0,.055),(.115,.075,.06),rock);save('stone')
stone('Ore matrix',(0,0,.065),(.10,.085,.075),rock)
for i in range(9):
 a=i*2.4;stone('Exposed iron seam',(math.cos(a)*.065,math.sin(a)*.06,.085+random.random()*.035),(.025,.026,.021),ore)
save('iron_ore')
uv('Venison joint',(0,0,.07),(.10,.065,.065),meat);bone=cyl('Bone shank',(.115,0,.065),.018,.12,fat);bone.rotation_euler[1]=math.pi/2
for y in [-.014,.014]:uv('Bone knuckle',(.18,y,.065),(.024,.02,.021),fat)
save('meat')
uv('Honey crock',(0,0,.075),(.068,.063,.071),honey);cyl('Jar neck',(0,0,.137),.046,.031,honey);cyl('Wooden lid',(0,0,.158),.052,.017,cut);tor('Lid binding',(0,0,.15),.049,.004,rope);uv('Lid handle',(0,0,.174),(.016,.016,.012),cut);save('honey')
for i in range(16):
 a=i*2.399;r=.015+.04*math.sqrt(i/16);uv('Ripe blackberry',(r*math.cos(a),r*math.sin(a),.025+random.random()*.029),(.017,.016,.018),berry)
for a in [0,2,4]:
 o=uv('Fresh leaves',(.035*math.cos(a),.035*math.sin(a),.055),(.035,.012,.003),green);o.rotation_euler[2]=a
save('berries')

import json
(OUT/'materials.json').write_text(json.dumps({m.name:{'color':list(m.diffuse_color)[:3],'metallic':m.node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value,'roughness':m.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value} for m in bpy.data.materials if m.use_nodes},indent=2))
