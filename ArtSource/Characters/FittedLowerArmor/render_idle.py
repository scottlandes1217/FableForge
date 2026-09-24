"""Use the exported gameplay MM_Idle sequence with the same outfit fit harness."""
import os
root=os.path.dirname(os.path.abspath(__file__))
s=open(root+'/render_run.py').read()
needle="original=next(o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('body_'));rig=next(m.object for m in original.modifiers if m.type=='ARMATURE')"
s=s.replace(needle,needle+"\n bpy.ops.import_scene.fbx(filepath=root+'/gameplay_idle.fbx');rig=next(o for o in bpy.context.selected_objects if o.type=='ARMATURE')")
s=s.replace("root+'/'+gender+'-", "root+'/'+gender+'-gameplay-idle-")
exec(compile(s,root+'/render_run.py','exec'))
